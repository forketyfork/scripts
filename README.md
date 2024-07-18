# scripts

These are some of the bash scripts that I use.

- [bookmarks.sh](bookmarks.sh): extract URLs from the macOS Safari Reading List
- [sr.sh](sr.sh): run an audio file through the Whisper speech recognition model
- [whisper-rebuild.sh](whisper-rebuid.sh): rebuild the [whisper.cpp](https://github.com/ggerganov/whisper.cpp) Whisper model locally

## git hooks
To install the pre-commit and post-commit hooks, after cloning, run the following command in the repository directory:
```sh
git config --local core.hooksPath hooks
```
