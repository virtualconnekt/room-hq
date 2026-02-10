/** @type {import('next').NextConfig} */
const nextConfig = {
    transpilePackages: ['@aptosroom/sdk'],
    webpack: (config, { isServer }) => {
        if (!isServer) {
            config.resolve.fallback = {
                ...config.resolve.fallback,
                got: false, // Node-only http client
                fs: false,
                net: false,
                tls: false,
                child_process: false,
                http: require.resolve('stream-http'),
                https: require.resolve('https-browserify'),
                zlib: require.resolve('browserify-zlib'),
                stream: require.resolve('stream-browserify'),
                url: require.resolve('url/'),
                buffer: require.resolve('buffer/'),
            };

            // Explicitly alias 'got' to empty module
            config.resolve.alias = {
                ...config.resolve.alias,
                got: require.resolve('./src/lib/empty-module.js'),
            };
        }
        return config;
    },
}

module.exports = nextConfig
