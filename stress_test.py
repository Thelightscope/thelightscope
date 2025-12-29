import argparse
from scapy.all import IP, TCP, Raw, conf
import random
import time
import string

# Set your network interface
iface = "em0"

# Parse command-line arguments
parser = argparse.ArgumentParser(description="Send packets starting at a given sequence number, a specific number of packets, and a delay between packets")
parser.add_argument("start_seq", type=int, help="Starting sequence number")
parser.add_argument("num_pkts", type=int, help="Number of packets to send")  # Added num_pkts argument
parser.add_argument("delay", type=float, help="Delay between packets in seconds")  # Added delay argument
args = parser.parse_args()

start_seq = args.start_seq
num_pkts = args.num_pkts  # Use the value from the command line argument
delay = args.delay  # Get the delay value from the command line argument

# Create five Layer3 sockets using the specified interface
sckt1 = conf.L3socket(iface)
sckt2 = conf.L3socket(iface)
sckt3 = conf.L3socket(iface)
sckt4 = conf.L3socket(iface)
sckt5 = conf.L3socket(iface)

# Create a list of sockets for easy round-robin selection
sockets = [sckt1, sckt2, sckt3, sckt4, sckt5]

target_ip = "192.168.206.128"

def random_port():
    """Return a random port between 0 and 65535 excluding ports 80 and 22."""
    while True:
        port = random.randint(60100, 60110)
        if port not in (80, 22):
            return port

def random_tcp_flags():
    return "S"
    """Randomly choose between 0 and 5 TCP flags from a common set."""
    flag_options = ['F', 'S', 'R', 'P', 'A', 'U']
    num_flags = random.randint(0, 5)
    if num_flags == 0:
        return ""
    return ''.join(random.sample(flag_options, num_flags))

def random_payload():
    """Generate a random payload of length between 0 and 200 characters."""
    length = random.randint(0, 200)
    if length == 0:
        return ""
    return ''.join(random.choices(string.ascii_letters + string.digits, k=length))

# Send packets starting with the provided sequence number
for i in range(num_pkts):
    seq = start_seq + i
    dport = random_port()             # Random destination port (excluding 80 and 22)
    flags = random_tcp_flags()         # Random TCP flags (0 to 5 flags)
    payload = random_payload()         # Random payload (0 to 200 characters)

    pkt = IP(dst=target_ip) / TCP(dport=dport, flags=flags, seq=seq) / Raw(load=payload)
    
    # Alternate sockets in round-robin: choose socket based on packet index
    current_socket = sockets[i % 5]
    
    # Retry sending until it succeeds
    sent = False
    while not sent:
        try:
            current_socket.send(pkt)
            sent = True
        except Exception as e:
            print(f"Error sending packet with seq {seq}: {e}", flush=True)
            time.sleep(0.1)  # wait a bit before retrying

    if seq % 100 == 0:
        print(f"Sent packet with sequence {seq} to port {dport} using socket {(i % 5) + 1}")
    time.sleep(delay)
