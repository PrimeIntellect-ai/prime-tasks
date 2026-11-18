import sys
import re

def redact(text):
    # Redact CC
    text = re.sub(r'\b(?:\d[ -]*?){13,16}\b', '[REDACTED_CC]', text)
    # Redact SSN
    text = re.sub(r'\b\d{3}-\d{2}-\d{4}\b', '[REDACTED_SSN]', text)
    # Neutralize HTML tags
    text = text.replace('<', '&lt;').replace('>', '&gt;')
    return text

if __name__ == "__main__":
    if len(sys.argv) > 1:
        print(redact(sys.argv[1]))
