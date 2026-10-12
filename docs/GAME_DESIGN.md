# Game design notes

The Project Bible is the specification. This file records where the build differs and why.

## The ball is simulated, not a physics body

The Bible asks for a physics body driven by forces. The build instead advances the ball in
road coordinates - distance along the road, offset across it, height above it - in fixed
1/60 s steps (`scripts/core/sim.gd`), and only draws it in 3D.

Why: nobody can test on a device during development, and a rigid body rolling over tile seams
is exactly the kind of thing that only shows its faults on a device. A deterministic
simulation can be played by a bot in a headless test, so "every level is passable" is checked
on every build instead of hoped for. Steering still works through acceleration and inertia,
bends push the ball outwards, slopes change its speed.

## Control

The ball rolls forward on its own. The finger steers left and right with a sliding joystick:
full steer at about a seventh of the screen width; the anchor follows the finger. Gaps are
jumped automatically from a ramp (the Bible keeps a jump button for later levels).

## Lives instead of a retry screen on every fall

A fall puts the ball back at the last checkpoint at once. Three falls end the attempt; the
fail card then offers a restart or one optional rewarded continue. A fall costs the third star.

## Cracked tiles

They drop a few metres ahead of the ball rather than under it: with a ball that never stops,
tiles that fall on contact would never matter. Cracks are visible from the start (the Bible's
honesty rule), and the tiles shake before they go.

## Left out of the first build

Purchases, Rewind (the Bible allows postponing it), banner ads, music, endless and daily modes.
Level 25 teaches long boosted jumps instead of Rewind.
