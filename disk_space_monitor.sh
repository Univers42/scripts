# **************************************************************************** #
#                                                                              #
#                                                         :::      ::::::::    #
#    disk_space_monitor.sh                              :+:      :+:    :+:    #
#                                                     +:+ +:+         +:+      #
#    By: dlesieur <dlesieur@student.42.fr>          +#+  +:+       +#+         #
#                                                 +#+#+#+#+#+   +#+            #
#    Created: 2026/05/18 21:19:26 by dlesieur          #+#    #+#              #
#    Updated: 2026/05/18 21:19:26 by dlesieur         ###   ########.fr        #
#                                                                              #
# **************************************************************************** #

#!/bin/bash
# Disk Space Monitor

THRESHOLD=80

USAGE=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')
if [ "$USAGE" -gt "$THRESHOLD" ]; then
  echo "Warning: Disk usage is at ${USAGE}%."
fi
