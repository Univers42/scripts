# **************************************************************************** #
#                                                                              #
#                                                         :::      ::::::::    #
#    verif_dependency.sh                                :+:      :+:    :+:    #
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

#!/usr/bin/env bash

set -e
REPO_DIR="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$REPO_DIR"

if [ ! -d "libft" ] || [ ! -f "libft/Makefile" ]; then
    echo "[hooks] init libft submodule..."
    git submodule update --init --recursive libft || true
fi

if [ -f "libft/Makefile" ]; then
    echo "[hooks] building libft..."
    (cd libft && make || true)
fi