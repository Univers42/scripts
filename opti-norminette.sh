# **************************************************************************** #
#                                                                              #
#                                                         :::      ::::::::    #
#    opti-norminette.sh                                 :+:      :+:    :+:    #
#                                                     +:+ +:+         +:+      #
#    By: dlesieur <dlesieur@student.42.fr>          +#+  +:+       +#+         #
#                                                 +#+#+#+#+#+   +#+            #
<<<<<<< HEAD
#    Created: 2026/05/18 21:19:26 by dlesieur          #+#    #+#              #
#    Updated: 2026/05/18 21:19:26 by dlesieur         ###   ########.fr        #
=======
#    Created: 2026/05/18 21:19:31 by dlesieur          #+#    #+#              #
#    Updated: 2026/05/18 21:19:31 by dlesieur         ###   ########.fr        #
>>>>>>> tmp/detached-a3c30f43
#                                                                              #
# **************************************************************************** #

norminette | awk '
/^[^ ]+\.[a-zA-Z0-9]+/ {file=$0; ok=0; next}
/: OK!$/ {ok=1; next}
NF && !ok {print file; print; ok=2}
!/: OK!$/ && ok==2 {print}
'
