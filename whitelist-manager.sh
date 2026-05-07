#!/bin/bash
# AI-Xray Whitelist Manager
# Interactive menu for managing domain whitelist

CONFIG_FILE="/etc/ai-xray/config.json"

# Colors
red='\e[91m'
green='\e[92m'
yellow='\e[93m'
cyan='\e[96m'
none='\e[0m'

# Check if config exists
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo -e "${red}Error: Config file not found at $CONFIG_FILE${none}"
    echo -e "${yellow}Please install AI-Xray first.${none}"
    exit 1
fi

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo -e "${yellow}Installing jq...${none}"
    if [[ -f /etc/debian_version ]]; then
        apt-get update -qq && apt-get install -y jq -qq
    elif [[ -f /etc/redhat-release ]]; then
        yum install -y jq -q
    fi
fi

show_menu() {
    clear
    echo -e "${cyan}========================================${none}"
    echo -e "${cyan}AI-Xray Whitelist Manager${none}"
    echo -e "${cyan}========================================${none}"
    echo ""
    echo -e "${green}Current whitelist domains:${none}"
    echo ""
    
    # Extract and display domains
    DOMAINS=$(jq -r '.routing.rules[0].domain[]' "$CONFIG_FILE" 2>/dev/null)
    
    if [[ -z "$DOMAINS" ]]; then
        echo -e "${yellow}No domains in whitelist${none}"
    else
        i=1
        while IFS= read -r domain; do
            echo -e "  ${cyan}[$i]${none} $domain"
            ((i++))
        done <<< "$DOMAINS"
    fi
    
    echo ""
    echo -e "${cyan}========================================${none}"
    echo -e "${green}Options:${none}"
    echo -e "  ${cyan}[d]${none} Delete a domain"
    echo -e "  ${cyan}[a]${none} Add a domain"
    echo -e "  ${cyan}[c]${none} Clear all (remove whitelist)"
    echo -e "  ${cyan}[r]${none} Restart Xray service"
    echo -e "  ${cyan}[q]${none} Quit"
    echo ""
    echo -ne "${green}Choose an option: ${none}"
}

delete_domain() {
    echo ""
    echo -ne "${green}Enter domain number to delete (or 'b' to go back): ${none}"
    read choice
    
    if [[ "$choice" == "b" ]]; then
        return
    fi
    
    # Get domain at index
    DOMAIN=$(jq -r ".routing.rules[0].domain[$((choice-1))]" "$CONFIG_FILE" 2>/dev/null)
    
    if [[ "$DOMAIN" == "null" || -z "$DOMAIN" ]]; then
        echo -e "${red}Invalid selection${none}"
        sleep 2
        return
    fi
    
    echo -e "${yellow}Deleting: $DOMAIN${none}"
    
    # Remove domain from array
    jq ".routing.rules[0].domain |= del(.[$(($choice-1))])" "$CONFIG_FILE" > /tmp/config.tmp && mv /tmp/config.tmp "$CONFIG_FILE"
    
    echo -e "${green}✓ Domain deleted${none}"
    echo -e "${yellow}Remember to restart Xray service (option 'r')${none}"
    sleep 2
}

add_domain() {
    echo ""
    echo -ne "${green}Enter domain to add (e.g., example.com): ${none}"
    read domain
    
    if [[ -z "$domain" ]]; then
        echo -e "${red}Domain cannot be empty${none}"
        sleep 2
        return
    fi
    
    # Add domain to array
    jq ".routing.rules[0].domain += [\"$domain\"]" "$CONFIG_FILE" > /tmp/config.tmp && mv /tmp/config.tmp "$CONFIG_FILE"
    
    echo -e "${green}✓ Domain added: $domain${none}"
    echo -e "${yellow}Remember to restart Xray service (option 'r')${none}"
    sleep 2
}

clear_all() {
    echo ""
    echo -e "${red}WARNING: This will remove ALL whitelist restrictions!${none}"
    echo -e "${yellow}Your proxy will work for ALL websites.${none}"
    echo ""
    echo -ne "${green}Are you sure? (yes/no): ${none}"
    read confirm
    
    if [[ "$confirm" != "yes" ]]; then
        echo -e "${yellow}Cancelled${none}"
        sleep 2
        return
    fi
    
    # Remove the domain rule entirely
    jq 'del(.routing.rules[0].domain)' "$CONFIG_FILE" > /tmp/config.tmp && mv /tmp/config.tmp "$CONFIG_FILE"
    
    echo -e "${green}✓ Whitelist cleared${none}"
    echo -e "${yellow}Remember to restart Xray service (option 'r')${none}"
    sleep 2
}

restart_service() {
    echo ""
    echo -e "${yellow}Restarting Xray service...${none}"
    systemctl restart xray
    
    if systemctl is-active --quiet xray; then
        echo -e "${green}✓ Xray restarted successfully${none}"
    else
        echo -e "${red}✗ Failed to restart Xray${none}"
        echo -e "${yellow}Check logs: journalctl -u xray -n 50${none}"
    fi
    
    sleep 3
}

# Main loop
while true; do
    show_menu
    read -n 1 option
    echo ""
    
    case $option in
        d|D)
            delete_domain
            ;;
        a|A)
            add_domain
            ;;
        c|C)
            clear_all
            ;;
        r|R)
            restart_service
            ;;
        q|Q)
            echo -e "${green}Goodbye!${none}"
            exit 0
            ;;
        *)
            echo -e "${red}Invalid option${none}"
            sleep 1
            ;;
    esac
done
