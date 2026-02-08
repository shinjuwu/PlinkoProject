#!/bin/sh
CAPTCHA=$(curl -s -X POST http://backend:9986/api/v1/login/captcha)
CID=$(echo "$CAPTCHA" | sed 's/.*captchaId":"//' | sed 's/".*//')
CVAL=$(echo "$CAPTCHA" | sed 's/.*captchaValue":"//' | sed 's/".*//')
echo "CID=$CID CVAL=$CVAL"

RESP=$(curl -s -X POST http://backend:9986/api/v1/login/login \
  -H 'Content-Type: application/json' \
  -d '{"username":"dccuser","password":"12345678","captchaId":"'"$CID"'","captcha":"'"$CVAL"'"}')
TOKEN=$(echo "$RESP" | sed 's/.*token":"//' | sed 's/".*//')
echo "LOGIN code=$(echo "$RESP" | sed 's/.*code"://' | sed 's/,.*//')"

echo "--- Testing post-login APIs ---"
for EP in /api/v1/global/getagentlist /api/v1/global/getallgamelist /api/v1/game/getgamelist /api/v1/servicestatus/getjobshedulerlist; do
  R=$(curl -s "http://backend:9986${EP}" -H "Token: ${TOKEN}")
  CODE=$(echo "$R" | sed 's/.*code"://' | sed 's/,.*//')
  echo "$EP => code=$CODE"
done
