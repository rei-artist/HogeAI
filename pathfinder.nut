/* $Id: main.nut 15101 2009-01-16 00:05:26Z truebrain $ */

/**
 * A Rail Pathfinder.
 */
class RailPathFinder
{
	static idCounter = IdCounter();
		
	_aystar_class = AyStar; //import("graph.aystar", "", 6);
	_max_cost = null;              ///< The maximum cost for a route.
	_cost_tile = null;             ///< The cost for a single tile.
	_cost_guide = null;
	_cost_diagonal_tile = null;    ///< The cost for a diagonal tile.
	_cost_doublediagonal_sea = null;
	_cost_turn = null;             ///< The cost that is added to _cost_tile if the direction changes.
	_cost_tight_turn = null;
	_cost_slope = null;            ///< The extra cost if a rail tile is sloped.
	_cost_bridge_per_tile = null;  ///< The cost per tile of a new bridge, this is added to _cost_tile.
	_cost_tunnel_per_tile = null;  ///< The cost per tile of a new tunnel, this is added to _cost_tile.
	_cost_tunnel_per_tile_ex = null;
	_cost_bridge_per_tile_ex = null;
	_cost_bridge_per_tile_ex2 = null;
	_cost_under_bridge = null;
	_cost_coast = null;            ///< The extra cost for a coast tile.
	_cost_crossing_rail = null;
	_cost_crossing_reverse = null;
	_cost_level_crossing = 0;
	_pathfinder = null;            ///< A reference to the used AyStar object.
	_max_bridge_length = null;     ///< The maximum length of a bridge that will be build.
	_max_tunnel_length = null;     ///< The maximum length of a tunnel that will be build.
	_bottom_ex_tunnel_length = null;
	_bottom_ex_bridge_length = null;
	_bottom_ex2_bridge_length = null;
	_can_build_water = null;
	_cost_water = null;
	_cost_danger = null;
	_estimate_rate = null;

	cost = null;                   ///< Used to change the costs.
	_running = null;
	_goals = null;
	_goalsMap = null;
	_count = null;
	_reverseNears = null;
	useInitializePath2 = false;
	
	
	cargo = null;
	platformLength = null;
	distance = null;
	dangerTiles = null;
	
	isFoundPath = false;
	
	constructor()
	{
		this._max_cost = 10000000;
		this._cost_tile = 100;
		this._cost_guide = 20;
		this._cost_diagonal_tile = 70;
		this._cost_doublediagonal_sea = 150;
		this._cost_turn = 50;
		this._cost_tight_turn = 200;
		this._cost_slope = 100;
		this._cost_bridge_per_tile = 150;
		this._cost_tunnel_per_tile = 120;
		this._cost_under_bridge = 100;
		this._cost_coast = 20;
		this._cost_crossing_rail = 50;
		this._cost_crossing_reverse = 100;
		this._max_bridge_length = 6;
		this._max_tunnel_length = 6;
		this._can_build_water = false;
		this._cost_water = 20;
		this._estimate_rate = 2;
		this._pathfinder = this._aystar_class(this, this._Cost, this._Estimate, this._Neighbours, this._CheckDirection);

		this.cost = this.Cost(this);
		this._running = false;
		this._count = idCounter.Get() * 1000;
		this._reverseNears = null;
		this._goalsMap = {};
		
		this.useInitializePath2 = false;
	}

		
	function InitializeParameters(isReverse) {
		_cost_level_crossing = 900;
		_cost_crossing_reverse = 300;
		_cost_bridge_per_tile_ex = 600;
		_cost_bridge_per_tile_ex2 = 900;
		_cost_tunnel_per_tile_ex  = 130;
		_cost_diagonal_tile = 67;
		_cost_doublediagonal_sea = 100000;
		_cost_guide = 300; //20;
		_cost_under_bridge = 50;	
		_cost_danger = 10000;

		
		_estimate_rate = 2;
		cost.tile = 100;
		cost.turn = 600;
		_cost_tight_turn = 1500; //isReverse ? 300 : 1500;
		cost.bridge_per_tile = 20;
		cost.tunnel_per_tile = 0;
		cost.coast = 0;
		cost.max_bridge_length = 30; //platformLength == null ? 11 : max( 7, platformLength * 3 / 2 );
		cost.max_tunnel_length = 11; //platformLength == null ? 11 : max( 7, platformLength * 3 / 2 );
		_bottom_ex_bridge_length = 7;
		_bottom_ex2_bridge_length = 11;
		_bottom_ex_tunnel_length = platformLength == null ? 7 : max( 7, platformLength );
		
		cost.slope = 0;
		if(/*!HogeAI.Get().IsRich() &&*/ cargo != null /*&& distance != null && distance < 250*/) {
			local trainPlanner = TrainPlanner();
			trainPlanner.cargo = cargo;
			trainPlanner.distance = distance == null ? 200 : distance;
			trainPlanner.productions = [100];
			trainPlanner.limitWagonEngines = 1;
			trainPlanner.skipWagonNum = 2;
			local engineSets = trainPlanner.GetEngineSetsOrder();
			if(engineSets.len()>=1 && AIEngine.GetMaxTractiveEffort(engineSets[0].trainEngine) < AIGameSettings.GetValue("vehicle.train_slope_steepness") * 150 /*100*/) {// engineSet.trainEngine AICompany.GetBankBalance(AICompany.COMPANY_SELF) > 500000) {
				HgLog.Info("TrainRoute: pathfinding consider slope");
				cost.slope = 1500;
				cost.turn = 100;
			}
		}
		
		if(HogeAI.Get().IsRich()) {
			cost.max_tunnel_length = 14; //platformLength == null ? 14 : max( 7, platformLength * 2 );
		} else if(!HogeAI.Get().HasIncome(100000)) {
			cost.max_tunnel_length = 0;
		}
		if(HogeAI.Get().CanRemoveWater()) {
			_can_build_water = true;
			_cost_water = -50;//50;
		}
		
		_InitializeDangerTiles();
	}
	
	function FindPathDay(limitDay,eventPoller) {
		return FindPath(null,eventPoller,limitDay);
	}
	
	function FindPath(limitCount,eventPoller,limitDay=null) {
		if(limitDay != null) {
			HgLog.Info("TrainRoute: Pathfinding...limit date:"+limitDay+" distance:"+distance);
		} else {
			HgLog.Info("TrainRoute: Pathfinding...limit count:"+limitCount+" distance:"+distance);
			limitCount *= 3;
		}
		local counter = 0;
		local path = false;
		local startDate = AIDate.GetCurrentDate();
		local endDate = limitDay != null ? startDate + limitDay : null;
		local totalInterval = 0;
		//PerformanceCounter.Clear();
		while (path == false && ((endDate!=null && AIDate.GetCurrentDate() < endDate + totalInterval) || (endDate==null && counter < limitCount))) {
			path = _FindPath(50);
			counter++;
//			HgLog.Info("counter:"+counter);
			local intervalStartDate = AIDate.GetCurrentDate();
			if(eventPoller != null && eventPoller.OnPathFindingInterval()==false) {
				HgLog.Warning("TrainRoute: FindPath break by OnPathFindingInterval");
				return null;
			}
			totalInterval += AIDate.GetCurrentDate() - intervalStartDate;
		}
		//PerformanceCounter.Print();
		
		if(path == false) { // 継続中
			path = _pathfinder._open.Peek();
		} else if(path != null) {
			HgLog.Info("TrainRoute: Path found. (count:" + counter + " date:"+ (AIDate.GetCurrentDate() - startDate - totalInterval) +") distance:"+distance);
			isFoundPath = true;
		} else {
			HgLog.Info("TrainRoute: FindPath failed");
		}
		if(path != null) {
			path = Path.FromPath(path);
			if(!isFoundPath) {
				while(path != null && AITile.HasTransportType(path.GetTile(), AITile.TRANSPORT_RAIL)) {
					HgLog.Info("tail tile is on rail:"+HgTile(path.GetTile()));
					path = path.GetParent();
				}
			}
			if(path != null) {
				path = RemoveConnectedHead(path);
				path = RemoveConnectedHead(path.Reverse()).Reverse();
			}
		}
		return path;
	}

	function RemoveConnectedHead(path) {
		local prev = null;
		local prevprev = null;
		local lastPath = path;
		while(path != null) {
			if(prev != null && prevprev != null) {
				if(RailPathFinder.AreTilesConnectedAndMine(prevprev.GetTile(),prev.GetTile(),path.GetTile())
						|| (AIBridge.IsBridgeTile(prevprev.GetTile()) && AIBridge.GetOtherBridgeEnd(prevprev.GetTile()) == prev.GetTile())
						|| (AITunnel.IsTunnelTile(prevprev.GetTile()) && AITunnel.GetOtherTunnelEnd(prevprev.GetTile()) == prev.GetTile())) {
					lastPath = prev;
				} else {
					break;
				}
			}
			prevprev = prev;
			prev = path;
			path = path.GetParent();
		}
		return lastPath;
	}
	
	function AreTilesConnectedAndMine(a,b,c) {
		return AIRail.AreTilesConnected(a,b,c) && AICompany.IsMine(AITile.GetOwner(b));
	}
		
	function IsFoundGoal() {
		return isFoundPath;
	}
	
	/**
	 * Initialize a path search between sources and goals.
	 * @param sources The source tiles.
	 * @param goals The target tiles.
	 * @param ignored_tiles An array of tiles that cannot occur in the final path.
	 * @see AyStar::InitializePath()
	 */
	function InitializePath(sources, goals, ignored_tiles = [], reversePath = null) {
		InitializeParameters(reversePath != null);
		if(sources[0].len() == 3) {
			_InitializePath2(sources, goals, ignored_tiles, reversePath);
			return;
		}
	
		local nsources = [];

		foreach (node in sources) {
			local path = this._pathfinder.Path(null, node[1], 0xFF, null, this._Cost, this);
			path = this._pathfinder.Path(path, node[0], 0xFF, null, this._Cost, this);
			nsources.push(path);
		}
		_InitializeGoals(goals);
		SetReversePath(reversePath);
		this._pathfinder.InitializePath(nsources, goals, ignored_tiles);
		
	}
	
	
	function _InitializePath2(sources, goals, ignored_tiles = [], reversePath=null) {
		local nsources = [];

		foreach (node in sources) {
			local path = this._pathfinder.Path(null, node[2], 0xFF, null, this._Cost, this);
			path = this._pathfinder.Path(path, node[1], 0xFF, null, this._Cost, this);
			path = this._pathfinder.Path(path, node[0], 0xFF, null, this._Cost, this);
			nsources.push(path);
		}
		_InitializeGoals(goals);
		SetReversePath(reversePath);
		this._pathfinder.InitializePath(nsources, goals, ignored_tiles);
		useInitializePath2 = true;
	}
	
	function _InitializeGoals(goals) {
		this._goals = goals;
		foreach(nodes in goals) {
			this._goalsMap[nodes[0]] <- nodes[1];
		}
	}
	
	function _InitializeDangerTiles() {
		if(dangerTiles != null) {
			local table = {};
			foreach(tile in dangerTiles) {
				table.rawset(tile,0);
			}
			dangerTiles = table;
		} else {
			dangerTiles = {};
		}
	}
	
	function SetReversePath(reversePath) {
		if(reversePath == null) {
			return;
		}
	
		//cost.bridge_per_tile = 100;
		//cost.tunnel_per_tile = 100;
		//_estimate_rate = 3;
		
		local nears = {};
		_reverseNears = {};
		
		local path = reversePath;
		while(path != null) {
			local tile = path.GetTile();
			nears.rawset(tile,0);
			_reverseNears.rawset(tile,0)
			path = path.GetParent();
		}
		for(local i=1; i<20; i++) {
			local next = {}
			foreach(tile,level in nears) {
				foreach(d in HgTile.DIR4Index) {
					if(!_reverseNears.rawin(tile+d)) {
						next.rawset(tile+d ,i)
						_reverseNears.rawset(tile+d ,i)
					}
				}
			}
			nears = next;
		}

	}

	/**
	 * Try to find the path as indicated with InitializePath with the lowest cost.
	 * @param iterations After how many iterations it should abort for a moment.
	 *  This value should either be -1 for infinite, or > 0. Any other value
	 *  aborts immediatly and will never find a path.
	 * @return A route if one was found, or false if the amount of iterations was
	 *  reached, or null if no path was found.
	 *  You can call this function over and over as long as it returns false,
	 *  which is an indication it is not yet done looking for a route.
	 * @see AyStar::FindPath()
	 */
	function _FindPath(iterations);
};

class RailPathFinder.Cost
{
	_main = null;

	function _set(idx, val)
	{
		if (this._main._running) throw("You are not allowed to change parameters of a running pathfinder.");

		switch (idx) {
			case "max_cost":          this._main._max_cost = val; break;
			case "tile":              this._main._cost_tile = val; break;
			case "diagonal_tile":     this._cost_diagonal_tile = val; break;
			case "turn":              this._main._cost_turn = val; break;
			case "slope":             this._main._cost_slope = val; break;
			case "bridge_per_tile":   this._main._cost_bridge_per_tile = val; break;
			case "tunnel_per_tile":   this._main._cost_tunnel_per_tile = val; break;
			case "coast":             this._main._cost_coast = val; break;
			case "max_bridge_length": this._main._max_bridge_length = val; break;
			case "max_tunnel_length": this._main._max_tunnel_length = val; break;
			default: throw("the index '" + idx + "' does not exist");
		}

		return val;
	}

	function _get(idx)
	{
		switch (idx) {
			case "max_cost":          return this._main._max_cost;
			case "tile":              return this._main._cost_tile;
			case "diagonal_tile":     return this._cost_diagonal_tile;
			case "turn":              return this._main._cost_turn;
			case "slope":             return this._main._cost_slope;
			case "bridge_per_tile":   return this._main._cost_bridge_per_tile;
			case "tunnel_per_tile":   return this._main._cost_tunnel_per_tile;
			case "coast":             return this._main._cost_coast;
			case "max_bridge_length": return this._main._max_bridge_length;
			case "max_tunnel_length": return this._main._max_tunnel_length;
			default: throw("the index '" + idx + "' does not exist");
		}
	}

	constructor(main)
	{
		this._main = main;
	}
};

function RailPathFinder::_FindPath(iterations) {
	//local c = PerformanceCounter.Start("FindPath");
	local result = __FindPath(iterations);
	//c.Stop();
	
	return result;
}


function RailPathFinder::__FindPath(iterations) {
	local test_mode = AITestMode();
	local ret = this._pathfinder.FindPath(iterations);
	this._running = (ret == false) ? true : false;
	if (!this._running && ret != null) {
		local goal2 = this._GetGoal2(ret.GetTile());
		if(goal2 != null) {
			return this._pathfinder.Path(ret, goal2, 0, null, this._Cost, this);
		}
	}
	return ret;
}

function RailPathFinder::_GetBridgeNumSlopes(end_a, end_b)
{
	local slopes = 0;
	local direction = (end_b - end_a) / AIMap.DistanceManhattan(end_a, end_b);
	local slope = AITile.GetSlope(end_a);
	if (!((slope == AITile.SLOPE_NE && direction == 1) || (slope == AITile.SLOPE_SE && direction == -AIMap.GetMapSizeX()) ||
		(slope == AITile.SLOPE_SW && direction == -1) || (slope == AITile.SLOPE_NW && direction == AIMap.GetMapSizeX()) ||
		 slope == AITile.SLOPE_N || slope == AITile.SLOPE_E || slope == AITile.SLOPE_S || slope == AITile.SLOPE_W)) {
		slopes++;
	}

	local slope = AITile.GetSlope(end_b);
	direction = -direction;
	if (!((slope == AITile.SLOPE_NE && direction == 1) || (slope == AITile.SLOPE_SE && direction == -AIMap.GetMapSizeX()) ||
		(slope == AITile.SLOPE_SW && direction == -1) || (slope == AITile.SLOPE_NW && direction == AIMap.GetMapSizeX()) ||
		 slope == AITile.SLOPE_N || slope == AITile.SLOPE_E || slope == AITile.SLOPE_S || slope == AITile.SLOPE_W)) {
		slopes++;
	}
	return slopes;
}

function RailPathFinder::_nonzero(a, b)
{
	return a != 0 ? a : b;
}

function RailPathFinder::_IsStraight(p1,p2,p3) {
	return RailPathFinder._GetDirectionIndex(p1,p2) == RailPathFinder._GetDirectionIndex(p2,p3);
}

function RailPathFinder::_GetDirectionIndex(p1,p2) {
	return (p2 - p1) / AIMap.DistanceManhattan(p1,p2);
}

function RailPathFinder::_Cost(self, path, new_tile, new_direction, mode) {
	//local counter = PerformanceCounter.Start("Cost");
	local result = RailPathFinder.__Cost(self, path, new_tile, mode, new_direction);
	//counter.Stop();
	return result;
}

function RailPathFinder::__Cost(self, path, new_tile, new_direction, mode)
{
	/* path == null means this is the first node of a path, so the cost is 0. */
	if (path == null) return 0;
	

	local prev_tile = path.GetTile();
	local par = path.GetParent();
	local parpar = par != null ? par.GetParent() : null;

	/* If the two tiles are more then 1 tile apart, the pathfinder wants a bridge or tunnel
	 *  to be build. It isn't an existing bridge / tunnel, as that case is already handled. */
	 
	local cost = 0;
	if(self._cost_tight_turn > 0 && par != null && parpar != null && parpar.GetParent() != null) {
		if(self._IsStraight(par.GetTile(), parpar.GetTile(), parpar.GetParent().GetTile())
				&& self._IsStraight(par.GetTile(), prev_tile, new_tile)
				&& self._GetDirectionIndex(par.GetTile(), parpar.GetTile()) != self._GetDirectionIndex(prev_tile, par.GetTile())) {
			cost += self._cost_tight_turn;
		}
	}

	if (AITile.HasTransportType(new_tile, AITile.TRANSPORT_ROAD)) cost += self._cost_level_crossing;

	local diagonal = false;
	local distance = AIMap.DistanceManhattan(new_tile, prev_tile);
	if (distance > 1) {
		/* Check if we should build a bridge or a tunnel. */

		local prevLength = 0;
		if(par != null && parpar != null) {
			prevLength = AIMap.DistanceManhattan(par.GetTile(), parpar.GetTile()) - 1;
		}
		local totalLength = distance + prevLength;
		if(mode != null && mode instanceof RailPathFinder.Underground) {
			cost += totalLength * (self._cost_tile + self._cost_tunnel_per_tile);
			if(totalLength > self._bottom_ex_tunnel_length) {
				cost += (distance - self._bottom_ex_tunnel_length) * self._cost_tunnel_per_tile_ex;
			}
		} else {
			cost += totalLength * (self._cost_tile + self._cost_bridge_per_tile);
			if(totalLength >= self._bottom_ex_bridge_length) {
				cost += (totalLength - (self._bottom_ex_bridge_length-1)) * self._cost_bridge_per_tile_ex;
			}
			if(totalLength >= self._bottom_ex2_bridge_length) {
				cost += (totalLength - (self._bottom_ex2_bridge_length-1)) * self._cost_bridge_per_tile_ex2;
			}
		}
		if(self._reverseNears != null) {
			local d = (prev_tile - new_tile)/ distance;
			for(local c = new_tile + d; c != prev_tile; c += d) {
				if(self._reverseNears.rawin(c)) {
					if(self._reverseNears[c] == 0) {
						cost += self._cost_crossing_reverse;
					}
				}
			}
		}
	} else {
		local diagonalSea = false;
		if (par != null && AIMap.DistanceManhattan(par.GetTile(), prev_tile) == 1 && par.GetTile() - prev_tile != prev_tile - new_tile) {
			diagonal = true;
			if(AITile.IsSeaTile(new_tile) && AITile.IsSeaTile(prev_tile) && parpar != null) {
				local parparpar = parpar.GetParent();
				if(parparpar != null 
						&& self._IsDiagonalDirection(par.GetDirection()) 
						&& self._IsDiagonalDirection(parpar.GetDirection()) 
						&& self._IsDiagonalDirection(parparpar.GetDirection())) {
					diagonalSea = true;// ナナメが4連続していた場合
				}
			}
		}
		if(diagonalSea) {
			cost += self._cost_doublediagonal_sea;
		} else if(diagonal) {
			cost += self._cost_diagonal_tile;
		} else {
			cost += self._cost_tile;
		}
		
		if (par != null && parpar != null &&
				AIMap.DistanceManhattan(new_tile, parpar.GetTile()) == 3 &&
				parpar.GetTile() - par.GetTile() != prev_tile - new_tile) {
			cost += self._cost_turn;
		}

		if (AITile.IsCoastTile(new_tile)) {
			cost += self._cost_coast;
		}
		if (AITile.IsSeaTile(new_tile)) {
			cost += self._cost_water;
		}
		if(self._cost_slope > 0) {
			if(parpar != null) {
				local h1 = AITile.GetMaxHeight (parpar.GetTile())
				local h2 = AITile.GetMaxHeight (new_tile);
				if(abs(h2-h1) >= 2) {
					cost += self._cost_slope;
				}
			}
		}
	}
	
	if(self._reverseNears != null) {
		if(self._reverseNears.rawin(new_tile)) {
			local level = self._reverseNears[new_tile];
			if(level == 1) {
				cost -= 50;
			} else if(diagonal && level == 0) {
				local tracks = AIRail.GetRailTracks(new_tile);
				if(tracks != AIRail.RAILTRACK_NE_SW && tracks != AIRail.RAILTRACK_NW_SE) {
					cost -= 50;
				} else {
					cost += 100;
				}
			}
		}
	} else {
		local prevDir = (prev_tile - new_tile) / distance;
		local dx = prevDir % AIMap.GetMapSizeX();
		local dy = prevDir / AIMap.GetMapSizeX();
		local revDir = dy - dx * AIMap.GetMapSizeX();
		if(!HogeAI.IsBuildable(prev_tile + revDir) || !HogeAI.IsBuildable(new_tile + revDir)) {
			cost += 500;
		}
		
	}
	
	if(self.dangerTiles.rawin(new_tile)) {
		//HgLog.Info("danger tile:"+HgTile(new_tile));
		cost += self._cost_danger;
	}

	return path.GetCost() + cost;
}

function RailPathFinder::_Estimate(self, cur_tile, cur_direction, goals) {
	//local counter = PerformanceCounter.Start("Estimate");

	local min_cost = self._max_cost;
	/* As estimate we multiply the lowest possible cost for a single tile with
	 *  with the minimum number of tiles we need to traverse. */
	foreach (goal in goals) {
		local dx = abs(AIMap.GetTileX(cur_tile) - AIMap.GetTileX(goal[0]));
		local dy = abs(AIMap.GetTileY(cur_tile) - AIMap.GetTileY(goal[0]));
		local goalCost = goal.len() >= 3 ? goal[2] : 0;
		
		min_cost = min(min_cost, min(dx, dy) * self._cost_diagonal_tile * 2 + (max(dx, dy) - min(dx, dy)) * self._cost_tile + goalCost);
	}
	
	local guide = 0;
	if(self._reverseNears != null) {
		if(self._reverseNears.rawin(cur_tile)) {
			local level = self._reverseNears[cur_tile];
			guide = self._cost_guide * level;
		} else {
			guide = self._cost_guide * 10;
		}
	}
	
	//counter.Stop();
	
	return min_cost * self._estimate_rate + guide;
}


function RailPathFinder::_CanChangeBridge(path, cur_node) {
	local tracks = AIRail.GetRailTracks(cur_node);
	local direction;
	if(tracks == AIRail.RAILTRACK_NE_SW) {
		direction = AIMap.GetTileIndex(1, 0);
	} else if(tracks == AIRail.RAILTRACK_NW_SE) {
		direction = AIMap.GetTileIndex(0, 1);
	} else {
		return false;
	}
	local n_node = cur_node - direction;
	local p = path.GetParent();
	for(local i=0; i<=2; i++) {
		if(AIRail.GetRailTracks(n_node) != tracks 
				|| !AICompany.IsMine(AITile.GetOwner(n_node))
				|| _IsSlopedRail(n_node - direction, n_node, n_node + direction) 
				|| AITile.IsStationTile(n_node)
				|| _IsUnderBridge(n_node)  
				//|| p.Contains(n_node) これのせいでナナメに横切れない
				|| _GetGoal2(n_node) != null
				|| _IsGoal2(n_node)) {
			return false;
		}
		n_node += direction;
	}
	//HgLog.Info("_CanChangeBridge:"+HgTile(cur_node));
	return true;
}

function RailPathFinder::_IsUnderBridge(node) {
	local offsets = [AIMap.GetTileIndex(0, 1), AIMap.GetTileIndex(1, 0)];
	foreach(offset in offsets) {
		local c_node = node;
		for(local i=0; i<10; i++) {
			if(AIBridge.IsBridgeTile(c_node)) {
				local end = AIBridge.GetOtherBridgeEnd(c_node);
//				HgLog.Info("c_node:"+HgTile(c_node)+" node:"+HgTile(node)+" end:"+HgTile(end));
				if(end < node && node < c_node) {
//					HgLog.Warning("bridge found");
					return true;
				}
			}
			c_node += offset;
		}
	}
	return false;
}

function RailPathFinder::_IsCollideTunnel(start, end, level) {
	local offsets = [AIMap.GetTileIndex(0, 1), AIMap.GetTileIndex(1, 0)];
	local dir = abs(start - end) / AIMap.DistanceManhattan(start, end);
	for(local node = min(start,end) + dir; node < max(start,end); node += dir) {
		foreach(offset in offsets) {
			if(offset == dir) {
				continue;
			}
			local c_node = node;
			for(local i=0; i<13; i++) {
				if(AITunnel.IsTunnelTile(c_node) && AITile.GetMaxHeight(c_node) == level) {
					local end = AITunnel.GetOtherTunnelEnd(c_node);
					if(end < node && node < c_node) {
						return true;
					}
				}
				c_node += offset;
			}
		}
	}
	return false;
}

function RailPathFinder::_GetGoal2(node) {
	if(_goalsMap.rawin(node)) {
		return _goalsMap[node];
	}
	return null;
}

function RailPathFinder::_IsGoal2(node) {
	foreach (goal in this._goals) {
		if (goal[1] == node) {
			return true;
		}
	}
	return false;
}

function RailPathFinder::_IsInclude90DegreeTrack(target, parTile, curTile) {
	if(AIBridge.IsBridgeTile(target) || AITunnel.IsTunnelTile(target)) {
		//HgLog.Info("_IsInclude90DegreeTrack"+HgTile(target)+" "+HgTile(parTile)+" "+HgTile(curTile)+" false (tunnel or bridge)");
		return false;
	}
	foreach(neighbor in HgTile.GetConnectionTiles(target, AIRail.GetRailTracks (target))) {
		if(neighbor == curTile) {
			continue;
		}
		if(AIMap.DistanceManhattan(parTile,neighbor)==1) {
			//HgLog.Info("_IsInclude90DegreeTrack"+HgTile(target)+" "+HgTile(parTile)+" "+HgTile(curTile)+" true");
			return true;
		}
	}
	//HgLog.Info("_IsInclude90DegreeTrack"+HgTile(target)+" "+HgTile(parTile)+" "+HgTile(curTile)+" false");
	return false;
}

function RailPathFinder::_PermitedDiagonalOffset(track) {
	switch(track) {
		case AIRail.RAILTRACK_SW_SE:
			return [AIMap.GetTileIndex(-1, 0),AIMap.GetTileIndex(0, -1)];
		case AIRail.RAILTRACK_NE_SE:
			return [AIMap.GetTileIndex(1, 0),AIMap.GetTileIndex(0, -1)];
		case AIRail.RAILTRACK_NW_NE:
			return [AIMap.GetTileIndex(1, 0),AIMap.GetTileIndex(0, 1)];
		case AIRail.RAILTRACK_NW_SW:
			return [AIMap.GetTileIndex(-1, 0),AIMap.GetTileIndex(0, 1)];
	}
	return null;
}


function RailPathFinder::_Neighbours(self, path, cur_node) {
	//local counter = PerformanceCounter.Start("Neighbours");
	local result = RailPathFinder.__Neighbours(self, path, cur_node);
	//counter.Stop();
	
	return result;
}


// cur_node == path.GetTile()である。別に渡す意味あるの？
function RailPathFinder::__Neighbours(self, path, cur_node) {


	/* self._max_cost is the maximum path cost, if we go over it, the path isn't valid. */
	if (path.GetCost() >= self._max_cost) return [];
	
	local tiles = [];
	local offsets = HgTile.DIR4Index;
	local par = path.GetParent();
	local par_tile = par!=null ? par.GetTile() : null;
	local underBridge = false;
	local goal2 = self._GetGoal2(cur_node);
	if(par != null) {
		if(par.GetTile() == cur_node) {
			HgLog.Error("par.GetTile() == cur_node:" + HgTile(cur_node));
		}
	}
	
	local fork = false;
	if (AITile.HasTransportType(cur_node, AITile.TRANSPORT_RAIL) && AICompany.IsMine(AITile.GetOwner(cur_node))) {
		if(goal2 != null || par==null || par.GetParent()==null || (self.useInitializePath2 && par.GetParent().GetParent() == null) /*これのせいでナナメに横切れない???*/) { // start or goal tile
			fork = true;
		} else if(BuildedPath.Contains(cur_node)) {
			if(!HgTile.IsDiagonalTrack(AIRail.GetRailTracks(cur_node))) {
				if(!self._CanChangeBridge(path, cur_node)) {
					return [];
				}
				//HgLog.Info("_CanChangeBridge:"+HgTile(cur_node));
				underBridge = true;
			} else {
				if(self._reverseNears != null && self._reverseNears.rawin(cur_node) && self._reverseNears[cur_node]==0) {
					offsets = self._PermitedDiagonalOffset(AIRail.GetRailTracks(cur_node));
					if(offsets==null) {
						return [];
					}
				} else {
					return [];
				}
			}
		}
	}

	/* Check if the current tile is part of a bridge or tunnel. */
	if (AIBridge.IsBridgeTile(cur_node) || AITunnel.IsTunnelTile(cur_node)) {
		/* We don't use existing rails, so neither existing bridges / tunnels. */
	} else if (par != null && AIMap.DistanceManhattan(cur_node, par_tile) > 1) {
		local other_end = par_tile;
		local dir = (cur_node - other_end) / AIMap.DistanceManhattan(cur_node, other_end);
		local next_tile = cur_node + dir;
//		tiles.push([next_tile, 1]);
		//HgLog.Info("DistanceManhattan > 1 isBuildableSea:" + isBuildableSea + " "+ HgTile(cur_node) + " next_tile:"+HgTile(next_tile));
		if(path.mode != null && path.mode instanceof RailPathFinder.Underground) {
			tiles.push([next_tile, self._GetDirection(other_end, cur_node, next_tile, true)]);
		} else {
			foreach (offset in offsets) {
				if (self._BuildRail(cur_node, next_tile, next_tile + offset)) {
					tiles.push([next_tile, self._GetDirection(other_end, cur_node, next_tile, true)]);
				}
			}
		}
	} else {
		// [parpar]-<tunnel>-[par(PM_UNDERGROUND)][cur(slope)][next]
		if(par != null && par.mode != null && par.mode instanceof RailPathFinder.Underground) {
			local next_tile = cur_node + (cur_node - par_tile);
			foreach (offset in offsets) {
				if (self._BuildRail(cur_node, next_tile, next_tile + offset)) {
					tiles.push([next_tile, self._GetDirection(par_tile, cur_node, next_tile, true)]);
				}
			}
			return tiles;
		}
		
		/* Check all tiles adjacent to the current tile. */
		foreach (offset in offsets) {
			local next_tile = cur_node + offset;
			/* Don't turn back */
			if (par != null && next_tile == par_tile) continue;
			/* Disallow 90 degree turns */
			if (par != null && par.GetParent() != null &&
				next_tile - cur_node == par.GetParent().GetTile() - par_tile) continue;
			if (par != null && par.GetParent() == null &&
				self._IsInclude90DegreeTrack(par_tile, next_tile, cur_node)) continue;			
			/* We add them to the to the neighbours-list if we can build a rail to
			 *  them and no rail exists there. */
			if (par == null 
					|| (goal2 == null && self._BuildRail(par_tile, cur_node, next_tile))
					|| (goal2 == null && fork && !RailPathFinder.AreTilesConnectedAndMine(par_tile, cur_node, next_tile)
						&& (AITile.GetMaxHeight(cur_node) <= AITile.GetMaxHeight(next_tile) || AITile.IsSeaTile(next_tile))) //分岐の場合。信号、或いは通行中の列車のせいでBuildRailが失敗する事があるが成功
					|| (underBridge && self._IsSlopedRail(par_tile, cur_node, next_tile)) // 橋の下の垂直方向スロープは成功
					|| (goal2 == next_tile 
						&& (RailPathFinder.AreTilesConnectedAndMine(par_tile, cur_node, next_tile) || self._BuildRail(par_tile, cur_node, next_tile)
						&& !self._IsInclude90DegreeTrack(next_tile, par_tile, cur_node)))) {
				if (par != null) {
					tiles.push([next_tile, self._GetDirection(par_tile, cur_node, next_tile, false)]);
				} else {
					tiles.push([next_tile, self._GetDirection(null, cur_node, next_tile, false)]);
				}
			}
		}
		if (par != null /*&& par.GetParent() != null*/ && !underBridge) {
			local bridges = self._GetTunnelsBridges(par, par_tile, cur_node/*, self._GetDirection(par.GetParent().GetTile(), par_tile, cur_node, true)*/);
			foreach (tile in bridges) {
				tiles.push(tile);
			}
		}
	}
	/*
	local s = "";
	foreach(t in tiles) {
		s += HgTile(t[0])+",";
	}
	HgLog.Info("tiles:" + HgTile(cur_node)+" next:"+s+" "+f);*/
	return tiles;
}

function RailPathFinder::_IsBuildableSea(tile, next_tile) {
	return ( AITile.IsSeaTile(tile) || (AITile.IsCoastTile(tile) && AITile.IsBuildable(tile) && AITile.GetMaxHeight(tile) <= 1/*steep slopeを避ける*/) )
		&& _RaiseAtWater(tile,next_tile);
}

function RailPathFinder::_BuildRail(p1,p2,p3) {
	if(AIRail.BuildRail(p1,p2,p3)) {
		return true;
	}
	if(_can_build_water && _IsBuildableSea(p2, p3) && p1 != p3) {
		return true;
	}
	if(AIError.GetLastError() != AIError.ERR_AREA_NOT_CLEAR) {
		return false;
	}
	local r = CanDemolishRail(p2);
	if(r) {
		HgLog.Info("CanDemolishRail(RailPathFinder::_BuildRail):"+HgTile(p2));
	}
	return r;
}

function RailPathFinder::CanDemolishRail(p) {
	if(!AICompany.IsMine(AITile.GetOwner(p))) {
		return false;
	}
	if(AIRail.IsRailTile(p) || AIBridge.IsBridgeTile(p) || AITunnel.IsTunnelTile(p)) {
		return !BuildedPath.Contains(p);
	}
	return false;
}

function RailPathFinder::_RaiseAtWater(t0,t1) {
	if(!AIMap.IsValidTile(t1)) {
		return false;
	}
	if(AIMap.DistanceFromEdge (t1) <= 2) {
		return false;
	}
	if(HogeAI.Get().IsAvoidRemovingWater()) {
		return false;
	}
	local boundCorner = HgTile.GetCorners( HgTile(t0).GetDirection(HgTile(t1)) );
	if(AITile.GetCornerHeight(t0,boundCorner[0]) == 0 && AITile.GetCornerHeight(t0,boundCorner[1]) == 0) {
		local result = AITile.RaiseTile(t0,HgTile.GetSlopeFromCorner(boundCorner[0])) || AITile.RaiseTile(t0,HgTile.GetSlopeFromCorner(boundCorner[1]));
		return result;
	}
	return true;
}

function RailPathFinder::_CheckDirection(tile, existing_direction, new_direction, self)
{
	return false;
}

function RailPathFinder::_dir(from, to)
{
	if (from - to == 1) return 0;
	if (from - to == -1) return 1;
	if (from - to == AIMap.GetMapSizeX()) return 2;
	if (from - to == -AIMap.GetMapSizeX()) return 3;
	throw("Shouldn't come here in _dir");
}

function RailPathFinder::_GetDirection(pre_from, from, to, is_bridge)
{
	if (is_bridge) {
		local d = (from - to) / AIMap.DistanceManhattan(from,to);
		if (d == 1) return 1;
		if (d == -1) return 2;
		if (d == AIMap.GetMapSizeX()) return 4;
		if (d == -AIMap.GetMapSizeX()) return 8;
	}
	return 1 << (4 + (pre_from == null ? 0 : 4 * this._dir(pre_from, from)) + this._dir(from, to));
}

function RailPathFinder::_IsDiagonalDirection(direction) {
	local n = direction >> 4;
	local n1 = n % 16;
	local n2 = n / 16;
	if(n1 <=2 && 2 < n2) {
		return true;
	}
	if(2 < n1 && n2 <= 2) {
		return true;
	}
	return false;
}

function RailPathFinder::_BuildTunnelEntrance( A0, A1, A2, L, testMode = true ) {
	if(!testMode || (AITile.IsBuildable(A0) && AITile.IsBuildable(A1) && AITile.IsBuildable(A2))) {
		local boundHeights = HgTile.GetBoundHeights(A0, A1);
		local maxa1a2 = max(boundHeights[0],boundHeights[1]);
		local m = AITile.GetMinHeight(A2);
		if(!(maxa1a2 - 1 <= m)) {
			return false;
		}
		if(L < maxa1a2) {
			return false;
		}
		local l = AITile.GetMaxHeight(A2);
		if(l==m) {
			if(!(L-1 == l || L == l)) {
				return false;
			}
		} else {
			if(!(L==l && L-1==m)) {
				return false;
			}
		}
		local A3 = A2 + (A2 - A1);
		if(!(AITile.GetMaxHeight(A3) <= L+1)) {
			return false;
		}
		if(!HgTile.LevelBound(A2,A3,L) || !HgTile.LevelBound(A1,A2,L-1)) {
			return false;
		}
		return true;
	}
	return false;

}

function RailPathFinder::_GetUndergroundTunnel(A0, A1, A2, L=null) {
	// [last_node(slope)] [cur_node(tunnel_start)] [next]
	if(L == null) {
		local m = AITile.GetMinHeight(A2);
		local l = AITile.GetMaxHeight(A2);
		if(l==m) {
			local result = _GetUndergroundTunnel(A0, A1, A2, l);
			if(result != null) {
				return result;
			}
			return _GetUndergroundTunnel(A0, A1, A2, l+1);
		} else if(l+2 == m) { // tight slope
			L = l+1;
		} else {
			L = l;
		}
	}
	if(!_BuildTunnelEntrance(A0, A1, A2, L)) {
		return null;
	}
	local significant = false;
	local dir = A2 - A1;
	for (local i = 2; i <= this._max_tunnel_length; i++) {
		local C = A2 + (i-1) * dir;
		if(AITile.IsSeaTile(C) || AITile.IsCoastTile(C)) {
			return null;
		}
		if(!AITile.IsBuildable(C) || AITile.GetMaxHeight(C) >= L + 1) {
			significant = true;
		}
		local B2 = A2 + i * dir;
		local B1 = B2 + dir;
		local B0 = B1 + dir;
		if(significant && _BuildTunnelEntrance(B0, B1, B2, L)) {
			if(_IsCollideTunnel(A2 ,B2, L)) {
				return null;
			}
			return [B2, _GetDirection(A0, A1, A2, true), RailPathFinder.Underground(L)];
		}
		if(AITile.GetMinHeight(B2) < L) {
			return null;
		}
	}
	return null;
}

/**
 * Get a list of all bridges and tunnels that can be build from the
 *  current tile. Bridges will only be build starting on non-flat tiles
 *  for performance reasons. Tunnels will only be build if no terraforming
 *  is needed on both ends.
 */
function RailPathFinder::_GetTunnelsBridges(par, last_node, cur_node)
{
	local tiles = [];
	
	local dir = cur_node - last_node;
	local next = cur_node + dir;
	
	if(par.GetParent()!=null) {
		local last_node2 = par.GetParent().GetTile();

		if(!AITile.IsBuildable(cur_node)) {
			return [];
		}
		
		if(dir == last_node - last_node2 && (!AITile.IsBuildable(next) || AITile.GetMaxHeight(cur_node) < AITile.GetMaxHeight(next)) && !AITile.IsSeaTile(next)) {
			// [last_node(slope)] [cur_node(tunnel_start)] [next]
			local tunnelEnd = _GetUndergroundTunnel(last_node2, last_node, cur_node);
			if(tunnelEnd != null) {
				//HgLog.Info("_GetUndergroundTunnel cur_node:" + HgTile(cur_node) + " target:"+HgTile(tunnelEnd[0]));
				tiles.push(tunnelEnd);
			}
		}
	}
	local bridge_dir = _GetDirection(par.GetTile(), cur_node, next, true);
	
	local significant = false;
	local level = AITile.GetMaxHeight(cur_node);
	if((!AITile.IsBuildable(next) && !HogeAI.IsPurchasedLand(next)) || level > AITile.GetMaxHeight(next)) {
		for (local i = 2; i < this._max_bridge_length; i++) {
			local bridge_list = AIBridgeList_Length(i + 1);
			local checkTile = cur_node + (i-1) * dir;
			if(!significant && (!AITile.IsBuildable(checkTile) || AITile.GetMaxHeight(checkTile) <= level - 2 || AITile.GetMaxHeight(checkTile) == level)) {
				significant = true;
			}
			local target = cur_node + i * dir;
			if (significant && !bridge_list.IsEmpty() && AIBridge.BuildBridge(AIVehicle.VT_RAIL, bridge_list.Begin(), cur_node, target)) {
				tiles.push([target, bridge_dir]);
			}
		}
		if(_can_build_water && _IsBuildableSea(cur_node, next)) {
			for (local i = 2; i < this._max_bridge_length; i++) {
				local checkTile = cur_node + (i-1) * dir;
				if(!((AITile.HasTransportType(checkTile, AITile.TRANSPORT_RAIL) || AITile.HasTransportType(checkTile, AITile.TRANSPORT_ROAD))
						&& AITile.GetMaxHeight(checkTile) == 1 && !_IsUnderBridge(checkTile) 
						&& (!AIBridge.IsBridgeTile(checkTile) || _IsFlatBridge(checkTile)))) {
					break;
				}
				if(AITile.IsStationTile(checkTile)) {
					break;
				}
				local target = cur_node + i * dir;
				if(_RaiseAtWater(checkTile, target) && _IsBuildableSea(target, target + dir)) {
					local bridge_list = AIBridgeList_Length(i + 1);
					if (!bridge_list.IsEmpty()) {
						tiles.push([target, bridge_dir, RailPathFinder.BridgeOnWater()]);
					}
				}
			}
		}
	}
	local slope = AITile.GetSlope(cur_node);
	if (slope != AITile.SLOPE_SW && slope != AITile.SLOPE_NW && slope != AITile.SLOPE_SE && slope != AITile.SLOPE_NE) {
		return tiles;
	}
	if(AITile.IsCoastTile(cur_node)) { //埋め立てられてトンネル作成に失敗するのを回避する
		return tiles;
	}
	
	local other_tunnel_end = AITunnel.GetOtherTunnelEnd(cur_node);
	if (!AIMap.IsValidTile(other_tunnel_end)) return tiles;

	local tunnel_length = AIMap.DistanceManhattan(cur_node, other_tunnel_end);
	local prev_tile = cur_node + (cur_node - other_tunnel_end) / tunnel_length;
	if (AITunnel.GetOtherTunnelEnd(other_tunnel_end) == cur_node && !AITile.IsCoastTile(other_tunnel_end) && tunnel_length >= 2 &&
			prev_tile == last_node && tunnel_length < _max_tunnel_length && AITunnel.BuildTunnel(AIVehicle.VT_RAIL, cur_node)) {
		//HgLog.Info("GetOtherTunnelEnd cur_node:" + HgTile(cur_node) + " target:"+HgTile(other_tunnel_end));
		tiles.push([other_tunnel_end, bridge_dir]);
	}
	return tiles;
}

function RailPathFinder::_IsSlopedRail(start, middle, end)
{
	local NW = 0; // Set to true if we want to build a rail to / from the north-west
	local NE = 0; // Set to true if we want to build a rail to / from the north-east
	local SW = 0; // Set to true if we want to build a rail to / from the south-west
	local SE = 0; // Set to true if we want to build a rail to / from the south-east

	if (middle - AIMap.GetMapSizeX() == start || middle - AIMap.GetMapSizeX() == end) NW = 1;
	if (middle - 1 == start || middle - 1 == end) NE = 1;
	if (middle + AIMap.GetMapSizeX() == start || middle + AIMap.GetMapSizeX() == end) SE = 1;
	if (middle + 1 == start || middle + 1 == end) SW = 1;

	/* If there is a turn in the current tile, it can't be sloped. */
	if ((NW || SE) && (NE || SW)) return false;

	local slope = AITile.GetSlope(middle);
	/* A rail on a steep slope is always sloped. */
	if (AITile.IsSteepSlope(slope)) return true;

	/* If only one corner is raised, the rail is sloped. */
	if (slope == AITile.SLOPE_N || slope == AITile.SLOPE_W) return true;
	if (slope == AITile.SLOPE_S || slope == AITile.SLOPE_E) return true;

	if (NW && (slope == AITile.SLOPE_NW || slope == AITile.SLOPE_SE)) return true;
	if (NE && (slope == AITile.SLOPE_NE || slope == AITile.SLOPE_SW)) return true;

	return false;
}

function RailPathFinder::_IsFlatBridge(start) {
	local end = AIBridge.GetOtherBridgeEnd(start);
	local dir = (end - start) / AIMap.DistanceManhattan(start,end);
	local h1 = AITile.GetMaxHeight(start);
	local h2 = AITile.GetMaxHeight(start + dir);
	return h2 < h1;
}

class RailPathFinder.Underground {
	level = null;

	constructor(level) {
		this.level = level;
	}
}

class RailPathFinder.BridgeOnWater {
}

class Pathfinding {
	
	industries = null;
	failed = null;
	
	constructor() {
		industries = [];
		failed = false;
	}
	
	function OnPathFindingInterval() {
		if(failed) {
			return false;
		}
		HogeAI.DoInterval();
		return true;
	}

	function OnIndustoryClose(industry) {
		foreach(i in industries) {
			if(i == industry) {
				failed = true;
			}
		}
	}

}
