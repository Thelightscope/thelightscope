---
- name: Deploy and run lightscope_core.py on host b
  hosts: b
  become: yes
  tasks:
    - name: Update apt cache
      apt:
        update_cache: yes

    - name: Install required apt packages
      apt:
        name:
          - libpcap-dev
          - python3-pip
          - python3.8-venv
        state: present

    - name: Create virtual environment in /root/here
      command: python3 -m venv /root/here
      args:
        creates: /root/here/bin/activate

    - name: Install required Python packages in the virtual environment
      pip:
        virtualenv: /root/here
        virtualenv_command: "python3 -m venv"
        name:
          - python-libpcap
          - scapy
          - psutil
          - requests
