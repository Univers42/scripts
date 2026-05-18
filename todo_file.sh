# **************************************************************************** #
#                                                                              #
#                                                         :::      ::::::::    #
#    todo_file.sh                                       :+:      :+:    :+:    #
#                                                     +:+ +:+         +:+      #
#    By: dlesieur <dlesieur@student.42.fr>          +#+  +:+       +#+         #
#                                                 +#+#+#+#+#+   +#+            #
#    Created: 2026/05/18 21:19:31 by dlesieur          #+#    #+#              #
#    Updated: 2026/05/18 21:19:31 by dlesieur         ###   ########.fr        #
#                                                                              #
# **************************************************************************** #

#!/bin/bash
# Todo List Manager

TODO_FILE=${1:-todo.txt}

case $1 in
  add)
    shift
    echo "$*" >> "$TODO_FILE"
    echo "Task added."
    ;;
  list)
    cat -n "$TODO_FILE"
    ;;
  remove)
    sed -i "${2}d" "$TODO_FILE"
    echo "Task removed."
    ;;
  *)
    echo "Usage: $0 {add|list|remove} [task|line_number]"
    ;;
esac
