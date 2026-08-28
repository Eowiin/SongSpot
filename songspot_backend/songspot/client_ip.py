"""Client address resolution for a deployment sitting behind one nginx proxy.

axes only reads its AXES_IPWARE_* settings when the optional django-ipware
package is installed, and it is not a dependency of this project. Without an
explicit resolver axes falls back to REMOTE_ADDR, which nginx makes identical
(127.0.0.1) for every request, so every failed login in the world lands in one
lockout bucket. See AXES_CLIENT_IP_CALLABLE in settings.py.
"""


def client_ip(request):
    """Return the address nginx actually accepted the connection from.

    nginx sets X-Forwarded-For to "$proxy_add_x_forwarded_for", which appends
    the peer address to whatever the client sent. The last entry is therefore
    the one nginx observed and the only one a client cannot forge; anything to
    its left is client-supplied and must not be trusted.
    """
    forwarded = request.META.get('HTTP_X_FORWARDED_FOR', '')
    hops = [hop.strip() for hop in forwarded.split(',') if hop.strip()]
    if hops:
        return hops[-1]
    return request.META.get('REMOTE_ADDR')
