#!/bin/bash

# set -x
# echo '#!/bin/bash
# /usr/bin/nohup /bin/bash /home/router/ppp-nat/delay-setup-multi-wan.sh > /dev/null 2>&1 & ;
# ' > /etc/ppp/ip-down.d/98-delay-setup-multi-wan.sh
# chmod +x /etc/ppp/ip-down.d/98-delay-setup-multi-wan.sh ;

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)";

sleep 3 ;

/bin/bash "$SCRIPT_DIR/setup-multi-wan.sh"
