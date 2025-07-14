from OpenSSL.crypto import FILETYPE_PEM, load_certificate
from os import listdir, makedirs, remove, system
from shutil import rmtree
from socket import gaierror, gethostbyname, setdefaulttimeout
from ssl import get_server_certificate, SSLError
from threading import Lock, Thread
from traceback import format_exc
import sys

# Configuration constants
ASNDB_FILE_NAME = 'rib.dat'
BLACKLIST_FILE_NAME = 'main.config'
DEFAULT_SOCKET_TIMEOUT = 5  # seconds
NUMBER_OF_THREADS = 50
TMP_DIR_NAME = './temp'
USE_CURL = True  # Use curl to get certificate info

class IPPool(object):
    """Manages and iterates through given IP ranges"""
    def __init__(self, *ip_ranges):
        assert len(ip_ranges) > 0, 'List of IP ranges is empty'
        
        self.lock = Lock()
        self._ip_ranges = list(ip_ranges)
        self._ip_ranges_info = {}
        
        for ip_range in self._ip_ranges:
            base_ip, mask = ip_range.split('/')
            mask = int(mask)
            
            # Convert to list for Python 3 compatibility
            base_ip_parts = list(map(int, base_ip.split('.')))
            
            self._ip_ranges_info[ip_range] = {
                'base_ip_parts': base_ip_parts,
                'caption': ip_range,
                'filename': f'{base_ip}({mask})_domains.txt',
                'length': 2 ** (32 - mask)
            }
            
        self._current_element_in_range = 1
        self._current_ip_range = 0
        self._exhausted = False
        
    def get_next_ip(self):
        """Thread-safe method to get next IP"""
        with self.lock:
            return self._get_next_ip()
            
    def _get_next_ip(self):
        """Get next IP in range (not thread-safe)"""
        if self._exhausted:
            return None
            
        # Get current IP range info
        ip_range = self._ip_ranges[self._current_ip_range]
        ip_range_info = self._ip_ranges_info[ip_range]
        
        # Calculate current IP
        ip_parts = [
            ip_range_info['base_ip_parts'][j] +
            (self._current_element_in_range // (256 ** (3 - j))) % 256
            for j in range(4)
        ]
        
        # Prepare result
        result = {
            'caption': ip_range_info['caption'] if self._current_element_in_range == 1 else None,
            'filename': ip_range_info['filename'],
            'ip': ip_parts
        }
        
        # Prepare for next iteration
        self._current_element_in_range += 1
        
        # Skip x.x.x.0 addresses
        if self._current_element_in_range % 256 == 0:
            self._current_element_in_range += 1
            
        # Check if current range is exhausted
        if self._current_element_in_range >= ip_range_info['length']:
            self._current_element_in_range = 1
            self._current_ip_range += 1
            
            # Check if all ranges are exhausted
            if self._current_ip_range >= len(self._ip_ranges):
                self._exhausted = True
                
        return result
        
    def resolve_ip_ranges(self):
        """Start worker threads to resolve IP ranges"""
        thread_pool = []
        
        for _ in range(NUMBER_OF_THREADS):
            worker = IPResolverWorker(self, self.lock)
            worker.daemon = True
            worker.start()
            thread_pool.append(worker)
            
        try:
            [t.join() for t in thread_pool]
        except KeyboardInterrupt:
            print('\nTerminating...')
            sys.exit(1)
        else:
            print('Finished.')

class IPPoolASN(IPPool):
    """Builds IP pool from ASN data for a given hostname"""
    def __init__(self, hostname):
        try:
            from pyasn import pyasn
        except ImportError:
            print("Installing pyasn module...")
            system('pip3 install pyasn')
            from pyasn import pyasn
            
        # Initialize ASN database
        try:
            asndb = pyasn(ASNDB_FILE_NAME)
        except IOError:
            print(f'File "{ASNDB_FILE_NAME}" missing. Setup? [y/n]')
            if input().strip().lower() == 'y':
                self._install_asndb()
                asndb = pyasn(ASNDB_FILE_NAME)
            else:
                raise RuntimeError(f'File "{ASNDB_FILE_NAME}" not found')
                
        # Get IP for hostname
        try:
            main_ip = gethostbyname(hostname)
        except gaierror:
            raise RuntimeError(f"Couldn't resolve IP for host: {hostname}")
            
        # Load blacklisted ranges
        self._ignored_ranges = []
        try:
            with open(BLACKLIST_FILE_NAME, 'r') as f:
                for i in f.read().split(','):
                    ip_range = i.strip()
                    if ip_range:
                        self._ignored_ranges.append(self._ip_range_to_range(ip_range))
        except IOError:
            print(f'File "{BLACKLIST_FILE_NAME}" missing, no IPs will be ignored')
            
        # Get ASN prefixes
        asn, _ = asndb.lookup(main_ip)
        ip_ranges = sorted(asndb.get_as_prefixes(asn))
        print(f'Found ASN ranges: {ip_ranges}')
        
        super().__init__(*ip_ranges)
        
    def get_next_ip(self):
        with self.lock:
            result = self._get_next_ip()
            while result is not None and self._ip_is_ignored(result['ip']):
                result = self._get_next_ip()
            return result
            
    @staticmethod
    def _install_asndb():
        """Download and install ASN database"""
        print("Downloading ASN database...")
        system('wget https://archive.org/download/routeviews_prefix-announcements/rib.dat')
        print("ASN database installed")
        
    @staticmethod
    def _ip_range_to_range(ip_range):
        """Convert IP range to min/max IP tuples"""
        base_ip, mask = ip_range.split('/')
        base_ip_parts = list(map(int, base_ip.split('.')))
        length = 2 ** (32 - int(mask))
        
        min_ip = base_ip_parts
        max_ip = [base_ip_parts[i] + (length // (256 ** (3 - i))) % 256 for i in range(4)]
        
        return min_ip, max_ip
        
    def _ip_is_ignored(self, ip):
        """Check if IP is in blacklisted range"""
        for min_ip, max_ip in self._ignored_ranges:
            if min_ip <= ip <= max_ip:
                return True
        return False

class IPResolverWorker(Thread):
    """Worker thread for resolving IPs to domain names"""
    _curl_param_str = (
        'curl -kvv --connect-timeout {timeout} --silent https://{ip} 2>&1 | '
        'awk \'BEGIN {{ FS = "CN=" }} ; {{print $2}}\' | '
        'awk \'NF\' | awk \'FNR%2\' > {out_file}'
    )
    _use_curl = USE_CURL

    def __init__(self, generator, lock):
        super().__init__()
        self.generator = generator
        self.lock = lock
        
    def run(self):
        while True:
            try:
                ip_info = self.generator.get_next_ip()
                if ip_info is None:
                    return
                    
                if ip_info['caption']:
                    with self.lock:
                        print(f'Testing {ip_info["caption"]}...')
                        
                ip_str = '.'.join(map(str, ip_info['ip']))
                resolved = self.resolve_name_for_ip(ip_str)
                
                if resolved:
                    with self.lock, open(ip_info['filename'], 'a+') as f:
                        f.write(f'https://{ip_str} - {resolved}\n')
                        f.flush()
                        print(f'[*] Domain found - https://{ip_str} - {resolved}')
                        
            except Exception:
                print(format_exc())
                
    def resolve_name_for_ip(self, ip):
        """Resolve hostname from SSL certificate"""
        if self._use_curl:
            # Use curl method
            out_file = f'{TMP_DIR_NAME}/{self.ident}'
            cmd = self._curl_param_str.format(
                ip=ip,
                timeout=DEFAULT_SOCKET_TIMEOUT,
                out_file=out_file
            )
            system(cmd)
            
            try:
                with open(out_file, 'r') as f:
                    content = f.read().strip()
                    if content:
                        return content.split(';')[0].strip()
            except IOError:
                return None
        else:
            # Use SSL library method
            try:
                cert = get_server_certificate((ip, 443))
                x509 = load_certificate(FILETYPE_PEM, cert)
                components = x509.get_subject().get_components()
                
                for name, value in components:
                    if name == b'CN':
                        return value.decode('utf-8')
            except (SSLError, gaierror, OSError, TimeoutError):
                return None

if __name__ == '__main__':
    setdefaulttimeout(DEFAULT_SOCKET_TIMEOUT)
    
    try:
        makedirs(TMP_DIR_NAME, exist_ok=True)
        
        print('Select an option:\n\t[1] Full ASN scan\n\t[2] Specific IPv4 range scan')
        choice = input().strip()
        
        if choice == '1':
            host = input('Enter hostname: ').strip()
            scanner = IPPoolASN(host)
        elif choice == '2':
            ip_range = input('Enter IP range (e.g., 104.36.195.0/24): ').strip()
            scanner = IPPool(ip_range)
        else:
            raise RuntimeError(f'Invalid option: {choice}')
            
        scanner.resolve_ip_ranges()
        
    except RuntimeError as e:
        print(f'Error: {str(e)}')
    except KeyboardInterrupt:
        print('\nOperation cancelled by user')
    except Exception as e:
        print(f'Unexpected error: {str(e)}')
        print(format_exc())
    finally:
        rmtree(TMP_DIR_NAME, ignore_errors=True)
