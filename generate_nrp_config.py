#!/usr/bin/env python3
"""Generate NRP-specific database name and config file"""

import datetime
import random
import string

# Generate database name
today = datetime.datetime.now().strftime('%Y%m%d')
rand_part = ''.join(random.choices(string.ascii_lowercase, k=50))
db_name = f'nrp{today}_{rand_part}'

# Write config file
with open('/opt/lightscope/config.ini', 'w') as f:
    f.write('[Settings]\n')
    f.write(f'database = {db_name}\n')
    f.write('self_telnet_and_ssh_honeypot_ports_to_forward = yes\n')
    f.write('autoupdate = yes\n')

print(f'Generated NRP database name: {db_name}')
