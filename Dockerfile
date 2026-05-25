# =============================================================================
# Isaac Lab + Isaac Sim + noVNC + SSH image for RunPod
# =============================================================================
#
# Base image:
#   NVIDIA's official Isaac Lab image already contains Isaac Sim and the
#   matching Isaac Lab runtime stack.
#
# Design goal:
#   /isaac-sim   -> Isaac Sim installation
#   /isaaclab    -> Isaac Lab source tree
#   /workspace   -> RunPod workspace / user projects / logs / checkpoints
#
# Important:
#   Do NOT place Isaac Lab below /workspace, because RunPod may mount a
#   persistent volume there and hide image-baked files.
# =============================================================================

FROM nvcr.io/nvidia/isaac-lab:2.3.2


# =============================================================================
# Global environment variables
# =============================================================================
#
# These variables make Isaac Sim and Isaac Lab discoverable from every shell,
# script and VSCode terminal session.
# =============================================================================

ENV ACCEPT_EULA=Y
ENV PRIVACY_CONSENT=Y
ENV OMNI_ENV_PRIVACY_CONSENT=Y
ENV OMNI_KIT_ALLOW_ROOT=1

ENV NVIDIA_VISIBLE_DEVICES=all
ENV NVIDIA_DRIVER_CAPABILITIES=all

ENV DISPLAY=:1

ENV ISAACSIM_PATH=/isaac-sim
ENV ISAACSIM_PYTHON_EXE=/isaac-sim/python.sh
ENV ISAACLAB_PATH=/isaaclab

ENV PATH=/isaaclab:/isaac-sim:${PATH}


# =============================================================================
# System packages
# =============================================================================
#
# Installs:
#   openssh-server  -> SSH access from VSCode / terminal
#   xvfb            -> virtual X server for headless GUI
#   x11vnc          -> VNC access to the virtual display
#   novnc/websockify-> browser-based VNC access via RunPod HTTP port
#   fluxbox/xterm   -> lightweight desktop environment
#   git/curl/tools  -> development and diagnostics
# =============================================================================

RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends \
        openssh-server \
        curl \
        git \
        iproute2 \
        net-tools \
        xvfb \
        x11vnc \
        novnc \
        websockify \
        fluxbox \
        xterm \
        mesa-utils && \
    mkdir -p /run/sshd && \
    rm -rf /var/lib/apt/lists/*


# =============================================================================
# SSH configuration
# =============================================================================
#
# Root login is allowed only via SSH public key.
# Password login is disabled.
# The public key is injected at runtime through the PUBLIC_KEY environment
# variable in RunPod.
# =============================================================================

RUN sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config && \
    sed -i 's/#PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config && \
    sed -i 's|#AuthorizedKeysFile.*|AuthorizedKeysFile .ssh/authorized_keys|' /etc/ssh/sshd_config && \
    echo "PasswordAuthentication no" >> /etc/ssh/sshd_config && \
    echo "ChallengeResponseAuthentication no" >> /etc/ssh/sshd_config


# =============================================================================
# Isaac Lab source tree
# =============================================================================
#
# The base image contains the runtime stack, but we install a clean and explicit
# Isaac Lab source tree under /isaaclab.
#
# Why /isaaclab?
#   It is outside /workspace, so it is not hidden by RunPod workspace mounts.
#   It is also cleaner than /opt/isaaclab for this single-purpose container.
#
# The _isaac_sim symlink is important because Isaac Lab scripts often use it
# to find Isaac Sim relative to the Isaac Lab directory.
# =============================================================================

RUN rm -rf /isaaclab && \
    git clone --branch v2.3.2 --depth 1 \
        https://github.com/isaac-sim/IsaacLab.git /isaaclab && \
    ln -sfn /isaac-sim /isaaclab/_isaac_sim && \
    chmod +x /isaaclab/isaaclab.sh


# =============================================================================
# Python and command-line convenience links
# =============================================================================
#
# python:
#   Some Isaac Lab scripts expect "python" to exist. Ubuntu images often only
#   provide "python3", so we create a compatibility symlink.
#
# isaaclab.sh:
#   Makes Isaac Lab callable from anywhere.
#
# isaac-python:
#   Explicit shortcut to Isaac Sim's Python interpreter.
# =============================================================================

RUN ln -sf /usr/bin/python3 /usr/bin/python && \
    ln -sf /isaaclab/isaaclab.sh /usr/local/bin/isaaclab.sh && \
    ln -sf /isaac-sim/python.sh /usr/local/bin/isaac-python


# =============================================================================
# Install Isaac Lab Python packages into Isaac Sim Python
# =============================================================================
#
# Editable installs keep the source tree usable for development and allow
# Isaac Lab tasks/assets/RL modules to be imported from Isaac Sim's Python.
# =============================================================================

RUN /isaac-sim/python.sh -m pip install -q -e /isaaclab/source/isaaclab && \
    /isaac-sim/python.sh -m pip install -q -e /isaaclab/source/isaaclab_assets && \
    /isaac-sim/python.sh -m pip install -q -e /isaaclab/source/isaaclab_tasks && \
    /isaac-sim/python.sh -m pip install -q -e /isaaclab/source/isaaclab_rl


# =============================================================================
# Shell startup configuration
# =============================================================================
#
# /etc/profile.d:
#   Makes the important Isaac paths available in login shells.
#
# .bashrc aliases:
#   Convenience commands for interactive work.
# =============================================================================

RUN printf '%s\n' \
    'export ISAACSIM_PATH=/isaac-sim' \
    'export ISAACSIM_PYTHON_EXE=/isaac-sim/python.sh' \
    'export ISAACLAB_PATH=/isaaclab' \
    'export PATH=/isaaclab:/isaac-sim:$PATH' \
    > /etc/profile.d/isaac_paths.sh && \
    chmod +x /etc/profile.d/isaac_paths.sh && \
    cat /etc/profile.d/isaac_paths.sh >> /root/.bashrc && \
    echo "alias python='/isaac-sim/python.sh'" >> /root/.bashrc && \
    echo "alias isaac-python='/isaac-sim/python.sh'" >> /root/.bashrc && \
    echo "alias isaaclab='/isaaclab/isaaclab.sh'" >> /root/.bashrc && \
    echo "alias isaaclab.sh='/isaaclab/isaaclab.sh'" >> /root/.bashrc && \
    echo "alias log-isaac='tail -f /tmp/isaac.log'" >> /root/.bashrc && \
    echo "alias log-novnc='tail -f /tmp/novnc.log'" >> /root/.bashrc && \
    echo "alias log-vnc='tail -f /tmp/x11vnc.log'" >> /root/.bashrc && \
    echo "alias log-xvfb='tail -f /tmp/xvfb.log'" >> /root/.bashrc && \
    echo "alias ports='ss -tulpn | grep -E \"22|5900|6080\"'" >> /root/.bashrc


# =============================================================================
# Build-time sanity checks
# =============================================================================
#
# These checks intentionally fail the Docker build if:
#   - Isaac Sim Python is missing
#   - Isaac Lab source is missing
#   - the _isaac_sim symlink is broken
#   - Isaac Lab cannot be imported
#   - isaaclab.sh cannot be called
# =============================================================================

RUN test -x /isaac-sim/python.sh && \
    test -f /isaaclab/isaaclab.sh && \
    test -L /isaaclab/_isaac_sim && \
    /isaac-sim/python.sh --version && \
    /isaac-sim/python.sh -c "import isaaclab; print('isaaclab import ok')" && \
    /isaaclab/isaaclab.sh --help >/tmp/isaaclab_help.txt


# =============================================================================
# Entrypoint
# =============================================================================
#
# Runtime sequence:
#   1. Install PUBLIC_KEY into /root/.ssh/authorized_keys
#   2. Start SSH
#   3. Start Xvfb virtual display
#   4. Start Fluxbox window manager
#   5. Start x11vnc
#   6. Start noVNC on port 6080
#   7. Start Isaac Sim GUI
#   8. Print diagnostics and keep container alive
# =============================================================================

RUN printf '%s\n' \
'#!/usr/bin/env bash' \
'set -e' \
'' \
'export DISPLAY=:1' \
'export ACCEPT_EULA=Y' \
'export PRIVACY_CONSENT=Y' \
'export OMNI_ENV_PRIVACY_CONSENT=Y' \
'export OMNI_KIT_ALLOW_ROOT=1' \
'export ISAACSIM_PATH=/isaac-sim' \
'export ISAACSIM_PYTHON_EXE=/isaac-sim/python.sh' \
'export ISAACLAB_PATH=/isaaclab' \
'export PATH=/isaaclab:/isaac-sim:$PATH' \
'' \
'echo "============================================================"' \
'echo "Container startup diagnostics"' \
'echo "============================================================"' \
'echo "ISAACSIM_PATH=${ISAACSIM_PATH}"' \
'echo "ISAACSIM_PYTHON_EXE=${ISAACSIM_PYTHON_EXE}"' \
'echo "ISAACLAB_PATH=${ISAACLAB_PATH}"' \
'echo "PATH=${PATH}"' \
'echo ""' \
'echo "Checking key paths..."' \
'ls -ld /isaac-sim || true' \
'ls -ld /isaaclab || true' \
'ls -ld /workspace || true' \
'ls -l /isaaclab/_isaac_sim || true' \
'echo ""' \
'echo "Checking commands..."' \
'which python || true' \
'which python3 || true' \
'which isaaclab.sh || true' \
'which isaac-python || true' \
'echo ""' \
'' \
'echo "Configuring SSH authorized_keys from PUBLIC_KEY..."' \
'mkdir -p /root/.ssh' \
'if [ -n "${PUBLIC_KEY}" ]; then' \
'  echo "${PUBLIC_KEY}" > /root/.ssh/authorized_keys' \
'  echo "PUBLIC_KEY installed into /root/.ssh/authorized_keys"' \
'else' \
'  echo "WARNING: PUBLIC_KEY environment variable is empty. SSH key login may fail."' \
'  touch /root/.ssh/authorized_keys' \
'fi' \
'chmod 700 /root/.ssh' \
'chmod 600 /root/.ssh/authorized_keys' \
'' \
'echo "Starting SSH..."' \
'mkdir -p /run/sshd' \
'/usr/sbin/sshd' \
'' \
'echo "Starting Xvfb..."' \
'Xvfb :1 -screen 0 1920x1080x24 -ac +extension GLX +render -noreset > /tmp/xvfb.log 2>&1 &' \
'sleep 2' \
'' \
'echo "Starting Fluxbox..."' \
'fluxbox > /tmp/fluxbox.log 2>&1 &' \
'sleep 2' \
'' \
'echo "Starting x11vnc..."' \
'x11vnc -display :1 -forever -shared -nopw -listen 0.0.0.0 -rfbport 5900 > /tmp/x11vnc.log 2>&1 &' \
'sleep 2' \
'' \
'echo "Starting noVNC on port 6080..."' \
'websockify --web=/usr/share/novnc/ 6080 localhost:5900 > /tmp/novnc.log 2>&1 &' \
'sleep 2' \
'' \
'echo "Starting Isaac Sim GUI..."' \
'cd /isaac-sim' \
'OMNI_KIT_ALLOW_ROOT=1 ./isaac-sim.sh > /tmp/isaac.log 2>&1 &' \
'' \
'echo ""' \
'echo "============================================================"' \
'echo "READY"' \
'echo "============================================================"' \
'echo "RunPod HTTP port: 6080"' \
'echo "RunPod TCP port: 22"' \
'echo "Optional direct VNC TCP port: 5900"' \
'echo ""' \
'echo "Useful checks:"' \
'echo "  echo \$ISAACSIM_PATH"' \
'echo "  echo \$ISAACLAB_PATH"' \
'echo "  isaaclab.sh --help"' \
'echo "  isaac-python --version"' \
'echo ""' \
'echo "Logs:"' \
'echo "  tail -f /tmp/isaac.log"' \
'echo "  tail -f /tmp/novnc.log"' \
'echo "  tail -f /tmp/x11vnc.log"' \
'echo "  tail -f /tmp/xvfb.log"' \
'echo "============================================================"' \
'echo ""' \
'' \
'tail -f /dev/null' \
> /entrypoint.sh && chmod +x /entrypoint.sh


# =============================================================================
# Exposed ports
# =============================================================================
#
# 22   -> SSH / VSCode Remote SSH
# 6080 -> noVNC browser UI
# 5900 -> direct VNC, optional
# =============================================================================

EXPOSE 22/tcp
EXPOSE 6080/tcp
EXPOSE 5900/tcp


# =============================================================================
# Container entrypoint
# =============================================================================

ENTRYPOINT ["/entrypoint.sh"]