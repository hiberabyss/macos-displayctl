CC := xcrun clang
CFLAGS := -Wall -Wextra -Werror -O2
LDLIBS := -framework ApplicationServices -framework CoreGraphics

TARGET := displayctl
SOURCE := displayctl.c

.PHONY: all clean rebuild

all: $(TARGET)

$(TARGET): $(SOURCE)
	$(CC) $(CFLAGS) $(SOURCE) $(LDLIBS) -o $(TARGET)

clean:
	rm -f $(TARGET)

rebuild: clean all
