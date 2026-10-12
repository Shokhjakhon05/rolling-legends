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

const SIDE_SPEED := 7.0             # top sideways speed at full steer
const SIDE_ACCEL := 34.0            # sideways response; higher = snappier
const CENTRIFUGAL := 0.55           # how hard a turn pushes the ball outwards (1 = real)
const GRAVITY := 24.0
const FALL_DEPTH := 7.0             # this far below the road the run is lost
const LAND_TOLERANCE := 0.75        # how far under the surface a landing is still caught

const HIT_BOUNCE := 0.42            # share of forward speed returned by a head-on hit
const HIT_SIDE_BOUNCE := 0.5
const OBSTACLE_HEIGHT := 1.3        # the ball clears an obstacle only above this height
const PICKUP_RADIUS := 0.95

const CRUMBLE_WARN := 15.0          # a cracked tile starts shaking this far ahead of the ball
const CRUMBLE_FALL := 6.5           # ...and drops this far ahead
const COLLAPSE_BEHIND := 9.0        # the road behind the ball falls away after this distance
const FINISH_PAD := 8
