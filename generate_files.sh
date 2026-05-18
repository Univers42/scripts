# **************************************************************************** #
#                                                                              #
#                                                         :::      ::::::::    #
#    generate_files.sh                                  :+:      :+:    :+:    #
#                                                     +:+ +:+         +:+      #
#    By: dlesieur <dlesieur@student.42.fr>          +#+  +:+       +#+         #
#                                                 +#+#+#+#+#+   +#+            #
<<<<<<< HEAD
#    Created: 2026/05/18 21:19:22 by dlesieur          #+#    #+#              #
#    Updated: 2026/05/18 21:19:22 by dlesieur         ###   ########.fr        #
=======
#    Created: 2026/05/18 21:19:26 by dlesieur          #+#    #+#              #
#    Updated: 2026/05/18 21:19:26 by dlesieur         ###   ########.fr        #
>>>>>>> tmp/detached-a3c30f43
#                                                                              #
# **************************************************************************** #

#!/bin/bash
export LC_ALL=C;
for n in {1..100}; do
	xxd -l $((RANDOM % 1024 + 1)) < /dev/urandom | cut -c 52- | tr -d '\n.' | tr '@' '\n' > tests/file$( printf %03d "$n").txt;
	echo '' >> tests/file$( printf %03d "$n").txt;
done
