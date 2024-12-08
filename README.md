# Get Tags
git fetch --tags --force

# Sync Tags if deleted remote
git fetch --prune origin +refs/tags/*:refs/tags/*

