import sys
import emoji

def count_emojis(text):
    return emoji.emoji_count(text)

def main():
    prev_count = 0
    for line in sys.stdin:
        current_count = count_emojis(line)
        if abs(current_count - prev_count) > 2:
            sys.stdout.write(line)
        prev_count = current_count

if __name__ == "__main__":
    main()
