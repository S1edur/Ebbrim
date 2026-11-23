#!/bin/bash
# Stand-in for `codex app-server` in tests. Logs each received method to
# $FAKE_LOG. FAKE_MODE: ok (default) | hang | signedout | exitafterinit |
# neterror | nomethod | serverrequest. In hang mode the child's pid goes to $FAKE_CHILD.
while IFS= read -r line; do
  method=$(printf '%s' "$line" | sed -n 's/.*"method":"\([^"]*\)".*/\1/p')
  id=$(printf '%s' "$line" | sed -n 's/.*"id":\([0-9]*\).*/\1/p')
  [ -n "$FAKE_LOG" ] && echo "$method" >> "$FAKE_LOG"
  case "$method" in
    initialize)
      echo '{"id":'"$id"',"result":{"userAgent":"fake"}}'
      [ "$FAKE_MODE" = exitafterinit ] && exit 0 ;;
    account/rateLimits/read)
      case "$FAKE_MODE" in
        hang) sleep 30 & echo $! > "$FAKE_CHILD"; wait ;;
        signedout) echo '{"id":'"$id"',"result":{"rateLimits":null}}' ;;
        neterror) echo '{"id":'"$id"',"error":{"code":-32603,"message":"stream disconnected before completion"}}' ;;
        nomethod) echo '{"id":'"$id"',"error":{"code":-32601,"message":"Method not found"}}' ;;
        serverrequest)
          echo '{"id":1,"method":"item/tool/requestUserInput","params":{}}'
          echo '{"id":'"$id"',"result":{"rateLimits":{"primary":{"usedPercent":5}}}}' ;;
        *) echo '{"method":"account/updated","params":{}}'
           echo '{"id":'"$id"',"result":{"accountId":"x","rateLimits":{"planType":"plus","primary":{"usedPercent":12,"windowDurationMins":300,"resetsAt":1763781300},"secondary":{"usedPercent":3,"windowDurationMins":10080,"resetsAt":1764353700}}}}' ;;
      esac ;;
  esac
done
