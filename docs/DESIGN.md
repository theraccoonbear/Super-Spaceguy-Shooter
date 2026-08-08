# Why this game, and why like this

## Where QB64-PE came from

I grew up learning QBasic on DOS. Eventually I got my hands on a QuickBasic compiler and used it to build games and little helper tools for D&D campaigns with friends, and that was the whole of my early "game dev" life. I hadn't touched QB in decades until a friend sent me a YouTube video of an older dev messing around with QB64, and something clicked: here was a chance to go back and actually build the "cool" game concepts I'd been fascinated by as a kid but never had the understanding or ability to pull off. The first one I went after was a 3D model renderer, with no OpenGL involved. My running joke is that we don't rely on a GPU here, we're just delighted to have a floating-point co-processor so our matrix transforms can be fast.

There's a real philosophy behind that choice, beyond nostalgia. When you build on a batteries-included framework, the outputs all tend to feel same-y, because you're working within someone else's defaults and it shows. What I loved as a kid was that essentially every game felt handcrafted, even when UI patterns repeated across titles in a sense. Development itself had a much more artisan feel to it. Building this from scratch in QB64-PE, without a game engine underneath me, is an attempt to recapture that. Every system in this codebase exists because I (with a lot of help) built it, not because a framework provided it.

## What the game is actually about

The tagline calls this "a political allegory wrapped in a love letter to 90s gaming." Both halves are meant literally.

The plotline is a direct response to the current political climate, and to a sense of helplessness and outrage at a lot of what's going on. The antagonist, Grotuk the Insatiable, is a proxy for a range of politicians and political malfeasance broadly, but he's inspired in principle by one specific, unnamed individual. The in-game atrocities that propel the story forward are meant to feel literally ripped from the headlines, not invented for the sake of having a villain.

I think most protest is largely ineffective as a path to actually fixing anything. It mostly happens to make the protester feel better, which is a legitimate thing to need, but not the same as remediation. This game is, to some degree, that: a safe way to vent. As for who it's for, honestly, anyone, from a pure "who can pick this up and play it" standpoint. I'd hope people who were gamers in the 80s and 90s find it charming and nostalgic, but it isn't made *for* people of my generation specifically. On the allegory side, my hope is that by decoupling the atrocities from the cult of personality around them, someone still under that sway might recognize the pattern anyway: that Emperor Grotuk wears no clothes.

## What's deliberate versus what just happened

Every sound in this game is synthesized from scratch, no audio files anywhere. That started out as practicality more than principle: it was the fastest way to get *something* audible into the game early on. But it turned out to fit the retro aesthetic so well that "some music" grew into a full pseudo-MIDI-lite composition system almost as a matter of course.

The speech synthesizer has a similar origin. Years earlier, during a research tangent related to the GIF/JIF pronunciation debate, I'd come across the CMU Pronouncing Dictionary. I got curious whether its ARPAbet phoneme data could reasonably drive formant synthesis for speech, and it turned out to work well enough to actually use. At that point, "generate everything procedurally" stopped being a cost-saving measure and became the obvious direction for the whole project. Sound, music, and speech are all synthesized; nothing is a recorded or authored asset.

Shipping a single binary with everything baked in was just common sense to me. There are plenty of pseudo-filesystem/packaging formats out there, but having one file with no supporting scaffolding felt like the right default, especially since QB64-PE's `$EMBED` makes it easy and this game's assets were never going to be that large to begin with.

Mostly, though, what counts as "deliberate" here comes down to this: whatever was state of the art for game development during my formative years became the standard the whole project gets measured against, whether or not that was ever stated as a rule up front.

## What "done" means

Realistically, what ships as v0.1 will function more like a v1.0 in spirit. I worry a lot about what I call "incremental demo fatigue," the risk that a player fires up build after build to see a handful of minor bug fixes and small improvements each time, and just gets tired of it before there's anything substantial to actually experience. Outside of some play testers along the way, my hope is that v0.1 releases fairly feature-complete and largely bug-free: a real, whole experience the first time someone outside that circle sees it, not a rough draft with a version number on it.

## The surprising part

If you were a QBasic developer back in the day, the thing that'll surprise you most is probably just how performant this game is. Part of that is simply that CPUs are a few orders of magnitude faster now than whatever you were running QBasic on. But I also suspect, without hard data to back it up, that QB64-PE transpiling to C++ and compiling against a real core library gets us meaningfully better performance than you could ever have squeezed out of a genuine QBasic executable on period-accurate hardware. It doesn't run like it's 1993, even though it's built to feel like it.
