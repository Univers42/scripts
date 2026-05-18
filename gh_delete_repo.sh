# **************************************************************************** #
#                                                                              #
#                                                         :::      ::::::::    #
#    gh_delete_repo.sh                                  :+:      :+:    :+:    #
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

# Ensure the user is logged into GitHub via gh CLI
if ! gh auth status &>/dev/null; then
  echo "You are not logged in. Please log in using 'gh auth login'."
  exit 1
fi

# Prompt the user to enter a space-separated list of repositories to delete
echo "Enter the list of repositories to delete (space-separated):"
read -r repos  # Read the list of repositories from standard input

# Loop through the repository list and delete each one
for repo in $repos; do
  echo "Attempting to delete repository: $repo"

  # Check if the repository exists before trying to delete it
  if gh repo view "LESdylan/$repo" &>/dev/null; then
    # Deleting repository with --yes flag to bypass confirmation
    gh repo delete "LESdylan/$repo" --yes
    echo "Repository '$repo' deleted successfully."
  else
    echo "Repository '$repo' does not exist or is inaccessible."
  fi
done