function notSupported(res) {
    res.writeHead(404, {
        'Content-Type': 'text/plain'
    });
    res.write('404');
    res.end();
}

function blockedForLegalReasons(res) {
    res.writeHead(451, {
        'Content-Type': 'text/plain'
    });
    res.write('Requested content is not available due to legal reasons.');
    res.end();
}

function errorBuilder(res, code = 500) {
    res.writeHead(code, {
        'Content-Type': 'text/plain'
    })
    res.write(`Error ${code}`)
    res.end()
}

function isError(res) {
    res.writeHead(500, {
        'Content-Type': 'text/plain'
    });
    res.write('500');
    res.end();
}

module.exports = {
    isError, notSupported, errorBuilder, blockedForLegalReasons
}