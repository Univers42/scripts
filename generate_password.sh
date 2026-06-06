# **************************************************************************** #
#                                                                              #
#                                                         :::      ::::::::    #
#    generate_password.sh                               :+:      :+:    :+:    #
#                                                     +:+ +:+         +:+      #
#    By: dlesieur <dlesieur@student.42.fr>          +#+  +:+       +#+         #
#                                                 +#+#+#+#+#+   +#+            #
#    Created: 2026/05/18 21:19:22 by dlesieur          #+#    #+#              #
#    Updated: 2026/05/18 21:19:22 by dlesieur         ###   ########.fr        #
#                                                                              #
# **************************************************************************** #

python3 - <<'PY'
import crypt
print(crypt.crypt('Test123!', crypt.mksalt(crypt.METHOD_BLOWFISH, rounds=2**12)))
PY
