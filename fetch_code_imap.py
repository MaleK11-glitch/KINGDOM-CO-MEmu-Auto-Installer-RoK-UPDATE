import imaplib
import email
import re
import sys

def fetch_code(email_addr, app_pass):
    try:
        # Connect to Gmail IMAP
        imap = imaplib.IMAP4_SSL("imap.gmail.com", 993, timeout=15)
        imap.login(email_addr, app_pass)
        imap.select("INBOX")
        
        # Search for emails from 'lilith'
        status, messages = imap.search(None, 'FROM', 'lilith')
        msg_ids = messages[0].split()
        if not msg_ids:
            print("No emails from Lilith found.")
            return None
            
        # Get the latest message
        last_id = msg_ids[-1]
        status, msg_data = imap.fetch(last_id, "(RFC822)")
        
        if status == "OK":
            raw = msg_data[0][1]
            msg = email.message_from_bytes(raw)
            
            body = ""
            if msg.is_multipart():
                for part in msg.walk():
                    ct = part.get_content_type()
                    if ct in ("text/plain", "text/html"):
                        payload = part.get_payload(decode=True)
                        if payload:
                            body += payload.decode(errors="ignore")
            else:
                payload = msg.get_payload(decode=True)
                if payload:
                    body = payload.decode(errors="ignore")
            
            # Try to find the code in the specific HTML tag first
            code_match = re.search(r'id="code"[^>]*>(\d{6})<', body)
            if code_match:
                return code_match.group(1)
                
            # Fallback: find any 6-digit number that isn't '000000'
            all_codes = re.findall(r'\b(\d{6})\b', body)
            real_codes = [c for c in all_codes if c != "000000"]
            if real_codes:
                return real_codes[0]
        
        imap.logout()
    except Exception as e:
        print(f"IMAP Error: {e}")
    return None

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: fetch_code_imap.py <email> <app_password>")
        sys.exit(1)
    
    res = fetch_code(sys.argv[1], sys.argv[2])
    if res:
        print(res)
    else:
        sys.exit(1)
