FROM nvcr.io/nvidia/isaac-lab:2.3.2

# EULA akzeptieren
ENV ACCEPT_EULA=Y
ENV PRIVACY_CONSENT=Y

# SSH einrichten
RUN mkdir -p ~/.ssh && \
    echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBL5t9+Uu8pY8E/ROoh2NEAR3cXinD0vxho/O6qMhAKy nadenau.marcus@gmx.de" \
    >> ~/.ssh/authorized_keys && \
    chmod 700 ~/.ssh && \
    chmod 600 ~/.ssh/authorized_keys

# Hilfreiche Aliases
RUN echo "alias python='/isaac-sim/python.sh'" >> ~/.bashrc && \
    echo "alias isaaclab='cd /workspace/IsaacLab && /isaac-sim/python.sh'" >> ~/.bashrc

# Container am Laufen halten
CMD ["sleep", "infinity"]
