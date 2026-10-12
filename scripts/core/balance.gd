## Every number that shapes how the ball feels, in one place (see docs/GAME_DESIGN.md).
extends RefCounted

const STEP := 1.0 / 60.0            # fixed simulation step, seconds
const BALL_RADIUS := 0.5
const COLS := 7                     # cells across the widest road
const CELL := 1.0                   # cell size, metres
const DEFAULT_WIDTH := 5

const SPEED := 9.0                  # cruising speed along the road, m/s
const SPEED_ACCEL := 7.0            # how fast the ball gets (back) to cruising speed
const SLOPE_SPEED := 9.0            # speed gained per unit of downhill slope
const BOOST_FACTOR := 1.55
const BOOST_TIME := 2.2

const SIDE_SPEED := 11.0            # top sideways speed at full steer
const SIDE_ACCEL := 95.0            # sideways response; higher = snappier
const STEER_GAIN := 7.0             # how hard the ball chases the spot the finger asks for
const CENTRIFUGAL := 0.55           # how hard a turn pushes the ball outwards (1 = real)
const GRAVITY := 24.0
const JUMP_SPEED := 8.6             # upward speed of a jump: about 6.4 m far at cruising speed
const JUMP_BUFFER := 0.14           # a jump pressed this early still happens on landing
const COYOTE := 0.1                 # ...and this late after rolling off an edge
const BRAKE := 14.0                 # how fast the ball stops after the finish line
const FALL_DEPTH := 7.0             # this far below the road the run is lost
const LAND_TOLERANCE := 0.75        # how far under the surface a landing is still caught

const HIT_BOUNCE := 0.42            # share of forward speed returned by a head-on hit
const HIT_SIDE_BOUNCE := 0.5
const BARRIER_HEIGHT := 1.15        # a barrier can be jumped: the ball clears it above this height
const TALL_HEIGHT := 2.6            # gates and pendulums cannot
const PICKUP_RADIUS := 0.95

const CRUMBLE_WARN := 15.0          # a cracked tile starts shaking this far ahead of the ball
const CRUMBLE_FALL := 6.5           # ...and drops this far ahead
const COLLAPSE_BEHIND := 9.0        # the road behind the ball falls away after this distance
const FINISH_PAD := 8
