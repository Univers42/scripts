# before we have to ask for permission admin or set them
gh auth refresh -h github.com -s delete_repo

# list and elimite all the repo
gh repo list --limit 100 --json nameWithOwner,isEmpty --jq '.[] | select(.isEmpty==true) | .nameWithOwner' | xargs -I {} gh repo delete {} --yes
