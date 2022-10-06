#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import sys
import os
import re
import codecs


def take_content_level(line):
    ret = 0
    for c in line:
        if c == '{':
            ret = ret + 1
        elif c == '}':
            ret = ret - 1
    return ret


if __name__ == "__main__":
    from_file = sys.argv[1]
    to_file = sys.argv[2]

    SERVER_CONFIGURE_RULE = re.compile('[^\\s,\\{\\}]+')
    SERVER_CONFIGURE_VALID_DOMAIN = re.compile(
        '(\\s*,?([\\w\\d\\-_\\.:]+|\\(\\s*[\\w\\d\\-_\\.:\\$]+\\s*\\)))+\\s*')
    output_content = []
    from_file_fd = codecs.open(from_file, "r", encoding='utf-8')
    server_block_level = 0
    last_domain_blocks = []
    last_domain_rules = []
    domain_blocks = set()
    for line in from_file_fd.readlines():
        line_striped = line.strip()
        if not line_striped:
            # keep empty
            if server_block_level > 0:
                last_domain_rules.append(line)
            else:
                output_content.append(line)
            continue
        elif line_striped[0:1] == '#':
            # keep comment
            if server_block_level > 0:
                last_domain_rules.append(line)
            else:
                output_content.append(line)
            continue

        if server_block_level > 0:
            server_block_level = server_block_level + take_content_level(line)
            last_domain_rules.append(line)
            if server_block_level <= 0:
                if last_domain_blocks:
                    output_content.append(',\n'.join(last_domain_blocks) +
                                          ' {\n')
                    output_content.append(''.join(last_domain_rules))
                last_domain_blocks = []
                last_domain_rules = []

        else:
            for server_block in SERVER_CONFIGURE_RULE.findall(line):
                if not SERVER_CONFIGURE_VALID_DOMAIN.match(server_block):
                    print(
                        '[WARNING]: {0} invalid, ignored'.format(server_block))
                    continue
                if server_block not in domain_blocks:
                    domain_blocks.add(server_block)
                    last_domain_blocks.append(server_block)
                else:
                    print('[WARNING]: {0} is already declared, ignored'.format(
                        server_block))

            server_block_level = server_block_level + take_content_level(line)
    from_file_fd.close()
    to_file_fd = codecs.open(to_file, "w", encoding='utf-8')
    to_file_fd.write(''.join(output_content))
    to_file_fd.close()
