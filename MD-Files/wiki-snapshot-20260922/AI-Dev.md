# AI & Development

Maze Linux is built to run AI workloads locally. The full stack — model runtime, utilities, build toolchain, and virtualization — ships preinstalled.

---

## Local AI Stack

### Ollama 0.3

Ollama 0.3.12 is a runtime for running large language models (LLMs) locally on your hardware, with no data leaving your machine. **Ollama starts on boot automatically** as a systemd service.

**Pull a model:**

```bash
ollama pull llama3
ollama pull mistral
ollama pull codellama
ollama pull phi3
```

**Run a model interactively:**

```bash
ollama run llama3
```

**List installed models:**

```bash
ollama list
```

**Remove a model:**

```bash
ollama rm llama3
```

**Start the API server:**

```bash
ollama serve
```

This starts a local HTTP API on `http://localhost:11434`. Compatible with the OpenAI API format.

**Check the service:**

```bash
systemctl status ollama
```

### Choosing a Model

| Model | Size | Best for |
|-------|------|---------|
| `llama3` | ~4.7 GB | General chat and reasoning |
| `codellama` | ~3.8 GB | Code generation and explanation |
| `mistral` | ~4.1 GB | Fast, capable general purpose |
| `phi3` | ~2.3 GB | Lightweight, fast on limited RAM |
| `llava` | ~4.5 GB | Vision — describe and analyze images |

Smaller models run on 8 GB RAM. Larger models (13B+) benefit from 16 GB+ RAM. GPU acceleration is used automatically if a CUDA or ROCm-compatible GPU is present.

### Ollama API

The REST API is compatible with the OpenAI chat completions format:

```bash
curl http://localhost:11434/api/chat -d '{
  "model": "llama3",
  "messages": [{"role": "user", "content": "Explain Btrfs snapshots in one paragraph."}]
}'
```

---

## Maze AI Utilities

### linux-chan-ai

The Maze **local model manager and chat interface**. Use it to pull and manage Ollama models, and to chat with any installed model — all in a terminal UI. Entirely local, no external API calls.

```bash
linux-chan-ai
```

### sentinai

An AI-assisted security monitoring tool. Analyzes system events, audit logs, and running processes to surface anomalies and potential threats.

```bash
sentinai
```

### Upscayl

AI image upscaling. Enlarges and enhances images using local neural network models — no cloud upload. Supports PNG, JPG, and WebP input at 2×, 4×, and 8× scale.

---

## Development Toolchain

### paru (AUR Helper)

```bash
paru -S <package>          # install from AUR or official repos
paru -Syu                  # update everything including AUR packages
paru -Ss <keyword>         # search
paru -Rns <package>        # remove package and unused dependencies
```

### base-devel

The full Arch build toolchain is preinstalled: `gcc`, `g++`, `make`, `cmake`, `binutils`, `autoconf`, `automake`, `fakeroot`, `patch`, `pkg-config`, and more.

### Python

Python 3 with `pip` and `setuptools` preinstalled:

```bash
pip install requests numpy pandas   # user install
paru -S python-numpy                 # system-wide from repo
```

### Git

```bash
git clone https://github.com/user/repo
git pull
```

### Node.js

Node.js is preinstalled:

```bash
node --version
npm install
```

### Rust (rustup)

The Rust toolchain is managed via `rustup`:

```bash
rustup show           # list installed toolchains
cargo new my-project  # start a new project
cargo build --release
```

### Go

The Go toolchain is preinstalled:

```bash
go version
go build ./...
```

### Flatpak (Additional Apps)

Flathub is configured. Install sandboxed developer tools:

```bash
flatpak install flathub com.visualstudio.code    # VS Code
flatpak install flathub com.jetbrains.PyCharm    # PyCharm
```

---

## Virtualization

### QEMU + KVM

Hardware-accelerated virtual machines. Your user is pre-added to the `kvm` and `libvirt` groups at install time.

Enable the libvirt daemon:

```bash
sudo systemctl enable --now libvirtd
```

Start the GUI:

```bash
virt-manager
```

Quick CLI VM:

```bash
qemu-system-x86_64 \
  -m 4G \
  -enable-kvm \
  -cpu host \
  -cdrom /path/to/image.iso \
  -drive file=disk.qcow2,format=qcow2 \
  -bios /usr/share/edk2/x64/OVMF.4m.fd
```

### Distrobox

Run containers from other distributions while sharing your home directory, display, and audio:

```bash
distrobox create --name ubuntu24 --image ubuntu:24.04
distrobox enter ubuntu24
distrobox stop ubuntu24
distrobox rm ubuntu24
```

---

## GPU Acceleration

Maze ships Vulkan and VA-API drivers for Intel, AMD, and Nvidia:

| GPU vendor | Vulkan package | Video decode |
|------------|---------------|-------------|
| Intel | `vulkan-intel` | `intel-media-driver` |
| AMD | `vulkan-radeon` | Mesa VA-API |
| Nvidia (open) | `vulkan-nouveau` | Mesa VA-API |
| Software | `vulkan-swrast` | Software fallback |

Check Vulkan support:

```bash
vulkaninfo | head -30
```

For Ollama GPU acceleration with Nvidia proprietary drivers:

```bash
sudo pacman -S nvidia nvidia-utils
OLLAMA_GPU=cuda ollama serve
```

For AMD ROCm (requires ROCm 6.1+ — older AMD GPUs fall back to CPU automatically):

```bash
OLLAMA_GPU=rocm ollama serve
```

---

## Zsh Environment

Zsh with Oh My Zsh is the default shell. It includes:

- The `maze` theme (custom prompt showing user, host, path, and git branch).
- Tab completion for `git`, `pacman`, `paru`, `docker`, and more.
- `fastfetch` runs at shell startup to show system info.

Customize in `~/.zshrc`. Add Oh My Zsh plugins:

```bash
# Edit ~/.zshrc, find the plugins line:
plugins=(git docker kubectl node)
```

---

## multilib and Flatpak

The `multilib` repository is enabled in `/etc/pacman.conf`, giving access to 32-bit libraries required for Steam, Wine, and game compatibility tools:

```bash
sudo pacman -S wine steam
```
