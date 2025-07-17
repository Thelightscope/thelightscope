#!/usr/bin/env python3
"""
Simple script to test GreyNoise API and show rate limit response
"""

import requests
import json

# GreyNoise API configuration (same as in query_abuse_ips.py)
GREYNOISE_API_KEY = "uHCLW5WzsZFHvguYGiFzDmNyELN3YDyjHQc3gyZWkcoySMTqHitYJvXi5Y9cEKxm"
GREYNOISE_QUICK_URL = "https://api.greynoise.io/v2/noise/quick/"

GREYNOISE_HEADERS = {
    "key": GREYNOISE_API_KEY,
    "Accept": "application/json",
    "User-Agent": "lightscope-analysis-script"
}

def test_greynoise_api():
    """Test GreyNoise API with a single lookup"""
    test_ip = "8.8.8.8"  # Use Google's DNS as a test IP
    
    print(f"Testing GreyNoise API with IP: {test_ip}")
    print(f"API URL: {GREYNOISE_QUICK_URL}{test_ip}")
    print(f"Headers: {GREYNOISE_HEADERS}")
    print("-" * 60)
    
    try:
        response = requests.get(GREYNOISE_QUICK_URL + test_ip, headers=GREYNOISE_HEADERS, timeout=30)
        
        print(f"Status Code: {response.status_code}")
        print(f"Response Headers: {dict(response.headers)}")
        print("-" * 60)
        print("Raw Response Text:")
        print(response.text)
        print("-" * 60)
        
        # Try to parse as JSON
        try:
            json_response = response.json()
            print("Parsed JSON Response:")
            print(json.dumps(json_response, indent=2))
        except json.JSONDecodeError:
            print("Response is not valid JSON")
            
    except requests.exceptions.RequestException as e:
        print(f"Request failed: {e}")
    except Exception as e:
        print(f"Unexpected error: {e}")

if __name__ == "__main__":
    test_greynoise_api() 