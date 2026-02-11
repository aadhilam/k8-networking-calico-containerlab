#!/bin/bash
# Helper script to capture packets and verify DSCP markings

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== DSCP Packet Capture Helper ===${NC}"
echo ""
echo "This script helps you capture packets to verify DSCP markings."
echo ""
echo "Select capture location:"
echo "  1) Router (eth3 - recommended, shows traffic with DSCP markings)"
echo "  2) Worker Node (eth1 - shows traffic leaving the node)"
echo "  3) Client (eth1 - shows incoming traffic)"
echo "  4) Compare all pods (captures from router and generates test traffic)"
echo ""
read -p "Enter choice [1-4]: " choice

case $choice in
    1)
        echo -e "${GREEN}Capturing on router (eth3)...${NC}"
        echo "Generating test traffic in 3 seconds..."
        echo "Press Ctrl+C to stop capture"
        sleep 3
        # Generate traffic in background
        (kubectl exec -it sender-dscp-af11 -- ping -c 10 10.30.30.100 > /dev/null 2>&1) &
        # Capture packets
        sudo docker exec -it clab-calico-dscp-router tcpdump -i eth3 -v -n 'ip' -c 20
        ;;
    2)
        echo -e "${GREEN}Capturing on worker node (eth1)...${NC}"
        echo "Generating test traffic in 3 seconds..."
        echo "Press Ctrl+C to stop capture"
        sleep 3
        (kubectl exec -it sender-dscp-af11 -- ping -c 10 10.30.30.100 > /dev/null 2>&1) &
        sudo docker exec -it clab-calico-dscp-k01-worker tcpdump -i eth1 -v -n 'ip' -c 20
        ;;
    3)
        echo -e "${GREEN}Capturing on client (eth1)...${NC}"
        echo "Generating test traffic in 3 seconds..."
        echo "Press Ctrl+C to stop capture"
        sleep 3
        (kubectl exec -it sender-dscp-af11 -- ping -c 10 10.30.30.100 > /dev/null 2>&1) &
        sudo docker exec -it clab-calico-dscp-client tcpdump -i eth1 -v -n 'ip' -c 20
        ;;
    4)
        echo -e "${GREEN}Comparing DSCP markings from all pods...${NC}"
        echo ""
        echo "Starting capture on router..."
        echo "Traffic will be generated from each pod..."
        echo ""
        
        # Start capture in background and save to file
        CAPTURE_FILE="/tmp/dscp-capture-$$.txt"
        sudo docker exec clab-calico-dscp-router tcpdump -i eth3 -v -n 'ip' -c 30 > "$CAPTURE_FILE" 2>&1 &
        CAPTURE_PID=$!
        
        sleep 2
        
        echo -e "${YELLOW}[1/3] Testing sender-no-dscp (should show tos 0x00)...${NC}"
        kubectl exec -it sender-no-dscp -- ping -c 3 10.30.30.100 > /dev/null 2>&1
        sleep 2
        
        echo -e "${YELLOW}[2/3] Testing sender-dscp-af11 (should show tos 0x28)...${NC}"
        kubectl exec -it sender-dscp-af11 -- ping -c 3 10.30.30.100 > /dev/null 2>&1
        sleep 2
        
        echo -e "${YELLOW}[3/3] Testing sender-dscp-ef (should show tos 0xb8)...${NC}"
        kubectl exec -it sender-dscp-ef -- ping -c 3 10.30.30.100 > /dev/null 2>&1
        sleep 2
        
        # Wait for capture to finish
        wait $CAPTURE_PID
        
        echo ""
        echo -e "${GREEN}=== Capture Results ===${NC}"
        echo ""
        echo "Looking for TOS values in captured packets:"
        echo ""
        grep -E "tos 0x" "$CAPTURE_FILE" | head -20 || echo "No TOS values found (packets may not have been captured)"
        echo ""
        echo "Full capture saved to: $CAPTURE_FILE"
        echo ""
        echo -e "${BLUE}Expected TOS values:${NC}"
        echo "  sender-no-dscp:   tos 0x00 (DSCP 0 - Default)"
        echo "  sender-dscp-af11: tos 0x28 (DSCP 10 - AF11)"
        echo "  sender-dscp-ef:   tos 0xb8 (DSCP 46 - EF)"
        ;;
    *)
        echo "Invalid choice. Exiting."
        exit 1
        ;;
esac

echo ""
echo -e "${GREEN}=== DSCP Value Reference ===${NC}"
echo "TOS byte = (DSCP << 2) | ECN"
echo ""
echo "DSCP 0  (DF/Default):    TOS 0x00 = 0"
echo "DSCP 10 (AF11):          TOS 0x28 = 40  (10 << 2)"
echo "DSCP 46 (EF):            TOS 0xb8 = 184 (46 << 2)"
echo ""
echo "Note: ECN bits (lower 2 bits) are usually 0 in this lab"
