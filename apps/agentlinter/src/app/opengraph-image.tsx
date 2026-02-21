import { ImageResponse } from 'next/og'

export const runtime = 'edge'
export const alt = 'AgentLinter - ESLint for AI Agents'
export const size = { width: 1200, height: 630 }
export const contentType = 'image/png'

export default function OGImage() {
  return new ImageResponse(
    (
      <div
        style={{
          width: '100%',
          height: '100%',
          background: 'linear-gradient(135deg, #0a0a0f 0%, #111118 50%, #0a0a0f 100%)',
          display: 'flex',
          flexDirection: 'column',
          alignItems: 'center',
          justifyContent: 'center',
          fontFamily: 'system-ui, -apple-system, sans-serif',
          position: 'relative',
        }}
      >
        {/* Subtle grid pattern */}
        <div
          style={{
            position: 'absolute',
            top: 0,
            left: 0,
            right: 0,
            bottom: 0,
            backgroundImage: 'radial-gradient(circle at 1px 1px, rgba(255,255,255,0.03) 1px, transparent 0)',
            backgroundSize: '40px 40px',
          }}
        />
        
        {/* DNA Helix Logo */}
        <svg width="120" height="120" viewBox="0 0 32 32" fill="none" style={{ marginBottom: 32 }}>
          {/* Left strand */}
          <path 
            d="M10 4 C10 9, 22 11, 22 16 C22 21, 10 23, 10 28" 
            stroke="#a78bfa" 
            strokeWidth="2.5" 
            strokeLinecap="round" 
            fill="none" 
          />
          {/* Right strand */}
          <path 
            d="M22 4 C22 9, 10 11, 10 16 C10 21, 22 23, 22 28" 
            stroke="#5eead4" 
            strokeWidth="2.5" 
            strokeLinecap="round" 
            fill="none" 
          />
          {/* Rungs */}
          <line x1="12" y1="8" x2="20" y2="8" stroke="rgba(255,255,255,0.15)" strokeWidth="1" />
          <line x1="14" y1="12.5" x2="18" y2="12.5" stroke="rgba(255,255,255,0.1)" strokeWidth="1" />
          <line x1="14" y1="19.5" x2="18" y2="19.5" stroke="rgba(255,255,255,0.1)" strokeWidth="1" />
          <line x1="12" y1="24" x2="20" y2="24" stroke="rgba(255,255,255,0.15)" strokeWidth="1" />
          {/* Nodes */}
          <circle cx="16" cy="10.5" r="2" fill="#a78bfa" />
          <circle cx="16" cy="16" r="2.5" fill="#5eead4" />
          <circle cx="16" cy="21.5" r="2" fill="#a78bfa" />
        </svg>

        {/* Title */}
        <div
          style={{
            fontSize: 72,
            fontWeight: 700,
            color: 'white',
            letterSpacing: '-0.02em',
            marginBottom: 16,
          }}
        >
          AgentLinter
        </div>

        {/* Tagline */}
        <div
          style={{
            fontSize: 32,
            color: 'rgba(255,255,255,0.6)',
            marginBottom: 48,
          }}
        >
          ESLint for AI Agents
        </div>

        {/* Command */}
        <div
          style={{
            display: 'flex',
            alignItems: 'center',
            gap: 12,
            padding: '16px 32px',
            background: 'rgba(255,255,255,0.05)',
            borderRadius: 12,
            border: '1px solid rgba(255,255,255,0.1)',
          }}
        >
          <span style={{ color: '#5eead4', fontSize: 24 }}>$</span>
          <span style={{ color: 'rgba(255,255,255,0.9)', fontSize: 24, fontFamily: 'monospace' }}>
            npx agentlinter
          </span>
        </div>

        {/* Footer */}
        <div
          style={{
            position: 'absolute',
            bottom: 40,
            display: 'flex',
            alignItems: 'center',
            gap: 8,
            color: 'rgba(255,255,255,0.4)',
            fontSize: 20,
          }}
        >
          Free & Open Source
        </div>
      </div>
    ),
    { ...size }
  )
}
