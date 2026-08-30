const repo = 'macinotch';
const isCI = process.env.GITHUB_ACTIONS === 'true';

/** @type {import('next').NextConfig} */
const nextConfig = {
  output: 'export',
  basePath: isCI ? `/${repo}` : '',
  assetPrefix: isCI ? `/${repo}/` : '',
  images: { unoptimized: true },
  trailingSlash: true,
  reactStrictMode: true,
  env: {
    NEXT_PUBLIC_BASE_PATH: isCI ? `/${repo}` : '',
  },
};

export default nextConfig;
