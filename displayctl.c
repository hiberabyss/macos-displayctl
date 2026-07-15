#include <ApplicationServices/ApplicationServices.h>
#include <CoreGraphics/CoreGraphics.h>
#include <dlfcn.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

typedef CGError (*CGSConfigureDisplayEnabledFn)(CGDisplayConfigRef, CGDirectDisplayID, bool);

static void print_display(CGDirectDisplayID id) {
    printf("%u\t%s\t%s\t%zux%zu\n",
           id,
           CGDisplayIsBuiltin(id) ? "built-in" : "external",
           CGDisplayIsActive(id) ? "active" : "inactive",
           CGDisplayPixelsWide(id),
           CGDisplayPixelsHigh(id));
}

static int get_online_displays(CGDirectDisplayID **displays, uint32_t *count) {
    CGError error = CGGetOnlineDisplayList(0, NULL, count);
    if (error != kCGErrorSuccess || *count == 0) {
        fprintf(stderr, "Unable to enumerate displays: %d\n", error);
        return 1;
    }

    *displays = calloc(*count, sizeof(**displays));
    if (*displays == NULL) {
        fprintf(stderr, "Out of memory\n");
        return 1;
    }

    error = CGGetOnlineDisplayList(*count, *displays, count);
    if (error != kCGErrorSuccess) {
        fprintf(stderr, "Unable to enumerate displays: %d\n", error);
        free(*displays);
        *displays = NULL;
        return 1;
    }
    return 0;
}

static bool selected(CGDirectDisplayID id, const char *target) {
    if (strcmp(target, "external") == 0)
        return !CGDisplayIsBuiltin(id);
    if (strcmp(target, "all") == 0)
        return true;

    char *end = NULL;
    unsigned long requested = strtoul(target, &end, 10);
    return end != target && *end == '\0' && requested == id;
}

static bool has_active_external_remaining(const CGDirectDisplayID *displays,
                                          uint32_t count,
                                          const char *target) {
    for (uint32_t i = 0; i < count; i++) {
        CGDirectDisplayID id = displays[i];
        if (!CGDisplayIsBuiltin(id) && CGDisplayIsActive(id) && !selected(id, target))
            return true;
    }
    return false;
}

static void state_path(char *path, size_t size) {
    snprintf(path, size, "/tmp/displayctl-disabled-%u", getuid());
}

static int save_disabled_externals(const CGDirectDisplayID *ids, uint32_t count) {
    char path[128];
    state_path(path, sizeof(path));
    FILE *file = fopen(path, "w");
    if (file == NULL) {
        perror("Unable to save disabled display IDs");
        return 1;
    }
    for (uint32_t i = 0; i < count; i++)
        fprintf(file, "%u\n", ids[i]);
    fclose(file);
    return 0;
}

static int configure(bool enabled, const char *target) {
    void *coreGraphics = dlopen(
        "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics",
        RTLD_NOW | RTLD_LOCAL);
    if (coreGraphics == NULL) {
        fprintf(stderr, "Unable to load CoreGraphics: %s\n", dlerror());
        return 1;
    }

    CGSConfigureDisplayEnabledFn setEnabled =
        (CGSConfigureDisplayEnabledFn)dlsym(coreGraphics, "CGSConfigureDisplayEnabled");
    if (setEnabled == NULL) {
        fprintf(stderr, "Private API CGSConfigureDisplayEnabled is unavailable\n");
        dlclose(coreGraphics);
        return 1;
    }

    CGDirectDisplayID *displays = NULL;
    uint32_t count = 0;
    char *targetEnd = NULL;
    unsigned long targetID = strtoul(target, &targetEnd, 10);
    bool directEnable = enabled && targetEnd != target && *targetEnd == '\0';
    if (!directEnable && get_online_displays(&displays, &count) != 0) {
        dlclose(coreGraphics);
        return 1;
    }

    CGDisplayConfigRef config = NULL;
    CGError error = CGBeginDisplayConfiguration(&config);
    if (error != kCGErrorSuccess) {
        fprintf(stderr, "Unable to begin display configuration: %d\n", error);
        free(displays);
        dlclose(coreGraphics);
        return 1;
    }

    uint32_t changed = 0;
    CGDirectDisplayID disabledExternals[32];
    uint32_t disabledExternalCount = 0;
    bool activeExternalWillRemain =
        enabled || has_active_external_remaining(displays, count, target);
    if (directEnable) {
        error = setEnabled(config, (CGDirectDisplayID)targetID, true);
        if (error != kCGErrorSuccess) {
            fprintf(stderr, "Private API rejected display %lu: %d\n", targetID, error);
            CGCancelDisplayConfiguration(config);
            dlclose(coreGraphics);
            return 1;
        }
        printf("Enabling display %lu\n", targetID);
        changed = 1;
    }
    for (uint32_t i = 0; i < count; i++) {
        CGDirectDisplayID id = displays[i];
        if (!selected(id, target))
            continue;
        if (!enabled && CGDisplayIsBuiltin(id) && !activeExternalWillRemain) {
            fprintf(stderr,
                    "Refusing to disable built-in display %u: "
                    "no active external display would remain\n",
                    id);
            continue;
        }

        error = setEnabled(config, id, enabled);
        if (error != kCGErrorSuccess) {
            fprintf(stderr, "Private API rejected display %u: %d\n", id, error);
            CGCancelDisplayConfiguration(config);
            free(displays);
            dlclose(coreGraphics);
            return 1;
        }
        printf("%s display %u\n", enabled ? "Enabling" : "Disabling", id);
        if (!enabled && !CGDisplayIsBuiltin(id) && disabledExternalCount < 32)
            disabledExternals[disabledExternalCount++] = id;
        changed++;
    }

    free(displays);
    dlclose(coreGraphics);

    if (changed == 0) {
        CGCancelDisplayConfiguration(config);
        fprintf(stderr, "No matching display found\n");
        return 1;
    }

    error = CGCompleteDisplayConfiguration(config, kCGConfigureForSession);
    if (error != kCGErrorSuccess) {
        fprintf(stderr, "Unable to apply display configuration: %d\n", error);
        return 1;
    }
    if (!enabled && strcmp(target, "external") == 0)
        return save_disabled_externals(disabledExternals, disabledExternalCount);
    return 0;
}

static int restore_disabled_externals(void) {
    char path[128];
    state_path(path, sizeof(path));
    FILE *file = fopen(path, "r");
    if (file == NULL) {
        fprintf(stderr, "No external displays previously disabled by displayctl\n");
        return 1;
    }

    unsigned int id;
    uint32_t restored = 0;
    int result = 0;
    while (fscanf(file, "%u", &id) == 1) {
        char target[16];
        snprintf(target, sizeof(target), "%u", id);
        if (configure(true, target) != 0)
            result = 1;
        else
            restored++;
    }
    fclose(file);
    if (result == 0 && restored > 0)
        unlink(path);
    return restored == 0 ? 1 : result;
}

static void usage(const char *program) {
    fprintf(stderr,
            "Usage:\n"
            "  %s list\n"
            "  %s off [external|display-id]\n"
            "  %s on  [external|display-id]\n",
            program, program, program);
}

int main(int argc, char **argv) {
    if (argc == 2 && strcmp(argv[1], "list") == 0) {
        CGDirectDisplayID *displays = NULL;
        uint32_t count = 0;
        if (get_online_displays(&displays, &count) != 0)
            return 1;
        for (uint32_t i = 0; i < count; i++)
            print_display(displays[i]);
        free(displays);
        return 0;
    }

    if (argc >= 2 && argc <= 3 && strcmp(argv[1], "off") == 0)
        return configure(false, argc == 3 ? argv[2] : "external");
    if (argc >= 2 && argc <= 3 && strcmp(argv[1], "on") == 0) {
        const char *target = argc == 3 ? argv[2] : "external";
        if (strcmp(target, "external") == 0)
            return restore_disabled_externals();
        return configure(true, target);
    }

    usage(argv[0]);
    return 2;
}