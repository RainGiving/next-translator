#!/bin/sh
# PopClip -> Next Translator. The app answers on a unix socket before doing
# any window work, so a healthy app responds in milliseconds.

send_text() {
    curl --silent --max-time 2 -d "$POPCLIP_TEXT" \
        --unix-socket /tmp/next-translator.sock http://next-translator
}

if send_text; then
    exit 0
fi

# Cold start: launch the app in the background, then poll with short sleeps.
open -g -a "Next Translator"
i=0
while [ $i -lt 40 ]; do
    sleep 0.25
    if send_text; then
        exit 0
    fi
    i=$((i + 1))
done
exit 1
