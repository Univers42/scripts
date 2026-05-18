# **************************************************************************** #
#                                                                              #
#                                                         :::      ::::::::    #
#    system_info_report.sh                              :+:      :+:    :+:    #
#                                                     +:+ +:+         +:+      #
#    By: dlesieur <dlesieur@student.42.fr>          +#+  +:+       +#+         #
#                                                 +#+#+#+#+#+   +#+            #
#    Created: 2026/05/18 21:19:26 by dlesieur          #+#    #+#              #
#    Updated: 2026/05/18 21:19:26 by dlesieur         ###   ########.fr        #
#                                                                              #
# **************************************************************************** #

#!/bin/bash
# System Info Report

echo "System Information Report"
echo "=========================="
echo "Uptime: $(uptime -p)"
echo "Disk Usage:"
df -h | grep '^/dev'
echo "Memory Usage:"
free -h
