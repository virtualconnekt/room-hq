"use client";

import React from "react";
import Link from "next/link";

export function Hero() {
    const features = [
        "Trustless work coordination",
        "Automated escrow & payouts",
        "On-chain submission verification",
        "No intermediaries. No disputes.",
    ];

    return (
        <>
            <style dangerouslySetInnerHTML={{
                __html: `
        @keyframes heroFadeInUp {
          from { opacity: 0; transform: translateY(16px); }
          to { opacity: 1; transform: translateY(0); }
        }
        @keyframes videoFocus {
          0% { transform: scale(1); }
          100% { transform: scale(1.04); }
        }
        .animate-hero {
          opacity: 0;
          animation: heroFadeInUp 400ms ease-out forwards;
        }
        .animate-video-focus {
          animation: videoFocus 20s ease-out forwards;
        }
        .delay-100 { animation-delay: 100ms; }
      `}} />
            <section className="relative w-full bg-[#000000] min-h-screen flex items-center justify-center py-20 px-6 sm:px-12 overflow-hidden">
                <div className="w-full max-w-[1280px] mx-auto grid grid-cols-1 lg:grid-cols-2 gap-16 lg:gap-24 items-center relative z-10">

                    <div className="flex flex-col items-start animate-hero relative z-20">
                        <h1 className="flex flex-col text-[#F2F2F2] text-4xl sm:text-5xl md:text-6xl lg:text-7xl uppercase tracking-tight leading-[1.05] max-w-xl mt-4">
                            <span className="font-normal text-[#F2F2F2]/85">Coordinate Work</span>
                            <span className="font-black text-[#00C4DE] mt-4">Without Trust</span>
                        </h1>

                        <p className="mt-14 text-[#9CA3AF] text-lg sm:text-xl font-medium max-w-lg leading-relaxed">
                            Objective evaluation. Automated settlement. Built on Aptos.
                        </p>

                        <ul className="mt-12 flex flex-col space-y-4">
                            {features.map((item, index) => (
                                <li
                                    key={index}
                                    className="flex items-center text-[#9CA3AF] font-medium text-base sm:text-lg"
                                >
                                    <svg className="w-5 h-5 text-[#00C4DE] mr-4 shrink-0 opacity-70" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth="2.5">
                                        <path strokeLinecap="round" strokeLinejoin="round" d="M5 13l4 4L19 7" />
                                    </svg>
                                    {item}
                                </li>
                            ))}
                        </ul>

                        <div className="mt-16 flex flex-col sm:flex-row items-center gap-5 w-full sm:w-auto">
                            <Link
                                href="/portal"
                                className="w-full sm:w-auto px-8 py-3.5 rounded-full bg-[#00C4DE] text-[#000000] font-medium text-base text-center transition-all duration-200 ease-out hover:bg-[#00D1EB] hover:-translate-y-[1px] hover:shadow-[0_4px_16px_rgba(0,196,222,0.15)] focus:outline-none focus:ring-2 focus:ring-[#00C4DE] focus:ring-offset-2 focus:ring-offset-[#000000]"
                            >
                                Launch a Room
                            </Link>

                            <Link
                                href="#protocol"
                                className="w-full sm:w-auto px-8 py-3.5 rounded-full bg-transparent border border-[#00C4DE]/20 text-[#00C4DE]/90 font-medium text-base text-center transition-all duration-200 ease-out hover:bg-[#00C4DE]/[0.03] hover:border-[#00C4DE]/30 focus:outline-none focus:ring-2 focus:ring-[#00C4DE] focus:ring-offset-2 focus:ring-offset-[#000000]"
                            >
                                Explore Protocol
                            </Link>
                        </div>
                    </div>

                    <div className="relative w-full aspect-square sm:aspect-video lg:aspect-square animate-hero delay-100 z-0 pointer-events-none">
                        <svg className="absolute w-0 h-0" aria-hidden="true">
                            <defs>
                                <clipPath id="hero-curve" clipPathUnits="objectBoundingBox">
                                    <path d="M 0.15 0 C 0.35 0.4, 0.25 0.7, 0.05 1 L 1 1 L 1 0 Z" />
                                </clipPath>
                            </defs>
                        </svg>

                        <div className="absolute top-1/2 -translate-y-1/2 left-[10%] md:left-[20%] lg:left-[35%] w-[120%] lg:w-[130%] h-[120%] lg:h-[130%]">
                            <div className="relative w-full h-full animate-video-focus origin-center" style={{ clipPath: 'url(#hero-curve)' }}>
                                <video
                                    src="/hero-video.mp4"
                                    autoPlay
                                    loop
                                    muted
                                    playsInline
                                    className="absolute inset-0 w-full h-full object-cover brightness-[0.98] contrast-100 saturate-[0.85] scale-[1.08]"
                                />
                                {/* Subtle vignette across the entire video frame */}
                                <div className="absolute inset-0 bg-[radial-gradient(ellipse_at_center,transparent_30%,#000000_100%)] opacity-50 z-20 pointer-events-none"></div>
                                {/* Extremely light noise texture overlay (2% opacity) */}
                                <div className="absolute inset-0 z-30 opacity-[0.02] mix-blend-overlay pointer-events-none" style={{ backgroundImage: 'url("data:image/svg+xml,%3Csvg viewBox=%220 0 200 200%22 xmlns=%22http://www.w3.org/2000/svg%22%3E%3Cfilter id=%22n%22%3E%3CfeTurbulence type=%22fractalNoise%22 baseFrequency=%220.8%22 numOctaves=%223%22 stitchTiles=%22stitch%22/%3E%3C/filter%3E%3Crect width=%22100%25%22 height=%22100%25%22 filter=%22url(%23n)%22/%3E%3C/svg%3E")' }}></div>
                            </div>
                        </div>
                    </div>

                </div>
            </section>
        </>
    );
}
