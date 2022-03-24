﻿
class RoadRoute extends CommonRoute {
	static instances = [];


	static function SaveStatics(data) {
		local a = [];
		foreach(route in RoadRoute.instances) {
			a.push(route.Save());
		}
		data.roadRoutes <- a;
	}
	
	static function LoadStatics(data) {
		RoadRoute.instances.clear();
		foreach(t in data.roadRoutes) {
			local route = RoadRoute();
			route.Load(t);
			
			HgLog.Info("load:"+route);
			
			RoadRoute.instances.push(route);	
			PlaceDictionary.Get().AddRoute(route);
		}
	}
	
	depots = null;
	roadType = null;
	
	constructor() {
		CommonRoute.constructor();
		depots = [];
	}
	
	function Save() {
		local t = CommonRoute.Save();
		t.depots <- depots;
		t.roadType <- roadType;
		return t;
	}
	
	function Load(t) {
		CommonRoute.Load(t);
		depots = t.depots;
		roadType = t.rawin("roadType") ? t.roadType : AIRoad.ROADTYPE_ROAD;
	}
	
	function Initialize() {
		CommonRoute.Initialize();
		roadType = AIRoad.GetCurrentRoadType();
		HgLog.Info("Initialize roadType:"+AIRoad.GetName(roadType)+" "+this);
	}
	
	function GetVehicleType() {
		return AIVehicle.VT_ROAD;
	}
	
	function GetMaxTotalVehicles() {
		return HogeAI.Get().maxRoadVehicle;
	}

	function GetThresholdVehicleNumRateForNewRoute() {
		return CommonRoute.IsSupportModeVt(AIVehicle.VT_ROAD) ? 0.8 : 0.95;
	}

	function GetThresholdVehicleNumRateForSupportRoute() {
		return 0.9;
	}
	
	function GetLabel() {
		return "Road";
	}

	function GetBuilderClass() {
		return RoadRouteBuilder;
	}
	
	function GetBuildingCost(distance) {
		return distance * HogeAI.Get().GetInflatedMoney(450);
	}

	function GetBuildingTime(distance) {
		return distance + 100;
	}
	
	
	function GetRoadType() {
		return roadType;
	}

	function SetPath(path) {
		if(GetDistance() < 150) {
			return;
		}
		local execMode = AIExecMode();
		local count = 0;
		while(path != null) {
			if(count % 100 == 99) {
				local depot = path.BuildDepot(GetVehicleType());
				if(depot != null) {
					depots.push(depot);
					HgLog.Info("Build middle depot."+HgTile(depot)+" "+this);
				} else {
					HgLog.Warning("Build middle depot failed."+this);
					
				}
			}
			count ++;
			path = path.GetParent();
		}
	}

	function AppendSrcToDestOrder(vehicle) {
		if(HogeAI.Get().IsEnableVehicleBreakdowns()) {
			foreach(depot in depots) {
				AIOrder.AppendOrder(vehicle, depot, AIOrder.OF_NON_STOP_INTERMEDIATE );
			}
		}
	}
	
	function AppendDestToSrcOrder(vehicle) {
		if(HogeAI.Get().IsEnableVehicleBreakdowns()) {
			foreach(i,depot in depots) {
				AIOrder.AppendOrder(vehicle, depots[depots.len()-i-1], AIOrder.OF_NON_STOP_INTERMEDIATE );
			}
		}
	}
	
	function IsSrcFullLoadOrder() {
		if(!HogeAI.Get().IsDistantJoinStations() && CargoUtils.IsPaxOrMail(cargo) && IsBiDirectional() && srcHgStation.place != null && srcHgStation.place instanceof TownCargo) {
			return false;
		} else {
			return true;
		}
	}

	function OnVehicleLost(vehicle) {
		HgLog.Warning("RoadRoute OnVehicleLost  "+this); //TODO 連続で来るのを抑制
		local execMode = AIExecMode();
		if(!RoadBuilder().BuildPath(destHgStation.GetEntrances(), srcHgStation.GetEntrances(), true)) {
			HgLog.Warning("RoadRoute removed.(Rebuild road failed) "+this);
			isClosed = true;
			isRemoved = true;
			foreach(vehicle,v in GetVehicleList()) {
				if((AIOrder.OF_STOP_IN_DEPOT & AIOrder.GetOrderFlags(vehicle, AIOrder.ORDER_CURRENT)) == 0) {
					AIVehicle.SendVehicleToDepot (vehicle);
				}
			}
		} else {
			HgLog.Warning("Rebuild road route succeeded");
		}
	}
}


class RoadRouteBuilder extends CommonRouteBuilder {
	
	static function BuildRoadUntilFree(p1,p2) {
		return BuildUtils.RetryUntilFree( function():(p1,p2) {
			return AIRoad.BuildRoad(p1,p2);
		});
	}
	
	constructor(dest, srcPlace, cargo) {
		CommonRouteBuilder.constructor(dest, srcPlace, cargo);
	}
	
	function GetRouteClass() {
		return RoadRoute;
	}
	
	function CreateStationFactory() { 
		return RoadStationFactory(cargo);
	}
	
	function CreatePathBuilder(engine, cargo) {
		return RoadBuilder(engine, cargo);
	}
	
	function BuildStart(engineSet) {
		foreach(roadType,v in AIRoadTypeList(AIRoad.ROADTRAMTYPES_ROAD )) {
			if(AIEngine.HasPowerOnRoad(engineSet.engine, roadType)) { //TODO 複数該当するケース。その場合は一番安いroadType?
				HgLog.Info("BuildStart RoadType:"+AIRoad.GetName(roadType)+" "+this);
				AIRoad.SetCurrentRoadType(roadType);
				return;
			}
		}
		foreach(roadType,v in AIRoadTypeList(AIRoad.ROADTRAMTYPES_TRAM )) {
			if(AIEngine.HasPowerOnRoad(engineSet.engine, roadType)) {
				HgLog.Info("BuildStart RoadType:"+AIRoad.GetName(roadType)+" "+this);
				AIRoad.SetCurrentRoadType(roadType);
				return;
			}
		}
		HgLog.Warning("Unkwown road type: engine"+AIEngine.GetName(engineSet.engine)+" "+this);
		AIRoad.SetCurrentRoadType(AIRoadTypeList(AIRoad.ROADTRAMTYPES_ROAD).Begin());
	}
}

class RoadBuilder {	
	path = null;
	cargo = null;
	engine = null;
	ignoreTiles = null;
	
	constructor(engine=null, cargo=null) {
		this.engine = engine;
		this.cargo = cargo;
		ignoreTiles = [];
	}

	function BuildPath(starts ,goals, suppressInterval=false) {
		local pathfinder = RoadPathFinder();
		local pathFindLimit = 100;
		pathfinder._cost_level_crossing = 1000;
		pathfinder._cost_drivethroughstation = 1000;
		pathfinder._cost_coast = 50;
		pathfinder._cost_slope = 0;
		pathfinder._cost_bridge_per_tile = 100;
		pathfinder._cost_tunnel_per_tile = 100;
		pathfinder._max_bridge_length = 20;
		if(!HogeAI.Get().IsRich()) {
			pathfinder._max_tunnel_length = 6;
		}
		if(IsConsiderSlope()) {
			pathfinder._cost_slope = 200;
			pathfinder._cost_no_existing_road = 100;
			pathfinder._cost_coast = 100;
			pathfinder._estimate_rate = 1;
			pathFindLimit = 500;
		}
		local distance = AIMap.DistanceManhattan(starts[0],goals[0]);
		/*
		if(distance > 200) {
			pathFindLimit = 400; // 3年とかかかったあげく失敗するとかヤバい
		}*/
		
		pathfinder.InitializePath(starts, goals, ignoreTiles);
		
		
		HgLog.Info("RoadRoute Pathfinding...limit:"+pathFindLimit+" distance:"+distance);
		local counter = 0;
		local path = false;
		while (path == false && counter < pathFindLimit) {
			path = pathfinder.FindPath(100);
			counter++;
			if(!suppressInterval) {
				HogeAI.DoInterval();
			}
		}
		if (path != null && path != false) {
			HgLog.Info("RoadRoute Path found. (" + counter + ")");
		} else {
			path = null;
			HgLog.Warning("RoadRoute Pathfinding failed.");
			return false;
		}
		this.path = path = Path.FromPath(path);
		local par;
		for (;path != null; path = par) {
			par = path.GetParent();
			if (par != null) {
				local isBridgeOrTunnel = AIBridge.IsBridgeTile(path.GetTile()) || AITunnel.IsTunnelTile(path.GetTile());
				if(isBridgeOrTunnel && AIRoad.HasRoadType(path.GetTile(),AIRoad.GetCurrentRoadType())) {
					local end = AIBridge.IsBridgeTile(path.GetTile())
						? AIBridge.GetOtherBridgeEnd(path.GetTile()) : AITunnel.GetOtherTunnelEnd(path.GetTile());
					if(end == par.GetTile()) {
						continue; // 既存橋トンネルの再利用
					} else {
						// 多分橋トンネルの出口。次の道路を作る
					}
				}
				if (AIMap.DistanceManhattan(path.GetTile(), par.GetTile()) == 1 ) {
					HogeAI.WaitForMoney(1000);
					if (!RoadRouteBuilder.BuildRoadUntilFree(path.GetTile(), par.GetTile())) {
						local error = AIError.GetLastError();
						if(error != AIError.ERR_ALREADY_BUILT) {
							HgLog.Warning("BuildRoad failed."+HgTile(path.GetTile())+" "+HgTile(par.GetTile())+" "+AIError.GetLastErrorString());
							return RetryBuildRoad(path, starts);
						}
					}
				} else {
					if (!isBridgeOrTunnel && AIRoad.IsRoadTile(path.GetTile())) {
						AITile.DemolishTile(path.GetTile());
					}
					HogeAI.WaitForMoney(20000);
					if (AITunnel.GetOtherTunnelEnd(path.GetTile()) == par.GetTile()) {
						if (!AITunnel.BuildTunnel(AIVehicle.VT_ROAD, path.GetTile())) {
							HgLog.Warning("BuildTunnel(Road) failed."+HgTile(path.GetTile())+" "+HgTile(par.GetTile())+" "+AIError.GetLastErrorString());
							return RetryBuildRoad(path, starts);
						}
					} else {
						local bridge_list = AIBridgeList_Length(AIMap.DistanceManhattan(path.GetTile(), par.GetTile()) + 1);
						bridge_list.Valuate(AIBridge.GetMaxSpeed);
						bridge_list.Sort(AIList.SORT_BY_VALUE, false);
						if (!AIBridge.BuildBridge(AIVehicle.VT_ROAD, bridge_list.Begin(), path.GetTile(), par.GetTile())) {
							HgLog.Warning("BuildBridge(Road) failed."+HgTile(path.GetTile())+" "+HgTile(par.GetTile())+" "+AIError.GetLastErrorString());
							return RetryBuildRoad(path, starts);
						}
					}
				}
			}
		}
		HgLog.Info("BuildRoad Pathfinding succeeded");
		return true;
	}
	
	function RetryBuildRoad(curPath, goals) {
		HgLog.Warning("RetryBuildRoad");
		//if(AIError.GetLastError() == AIError.ERR_NOT_ENOUGH_CASH) { // 高すぎて失敗した可能性があるため、繰り返さないようにする => 失敗したという事はPathFinderのバグの可能性あり。その場合無限ループする
			ignoreTiles.push(curPath.GetTile());
		//}
		local startPath = this.path.SubPathEnd(curPath.GetTile());
		if(startPath == null) {
			HgLog.Warning("No start tiles("+curPath.GetTile()+")");
			return false;
		}
		return BuildPath(startPath.GetTiles(), goals);
	}
	
	function IsConsiderSlope() {
		if(engine == null || cargo == null) {
			return false;
		}
		if(AICompany.GetBankBalance(AICompany.COMPANY_SELF) > 100000 && Route.GetAllRoutes().len()>=1) {
			return false;
		}
		local speed = AIEngine.GetMaxSpeed(engine);
		if(speed == 0) {
			HgLog.Warning("IsConsiderSlope speed == 0 "+AIEngine.GetName(engine));
		}
		local weight = VehicleUtils.GetCargoWeight(cargo, AIEngine.GetCapacity(engine));
		return VehicleUtils.GetForce(AIEngine.GetMaxTractiveEffort(engine), AIEngine.GetPower(engine), AIEngine.GetMaxSpeed(engine)/2) 
			- VehicleUtils.GetSlopeForce(weight,weight) < 0;
	}
	
}

class TownBus {
	
	static instances = [];
	static townMap = {};
	
	static function SaveStatics(data) {
		local array = [];
		foreach(townBus in TownBus.instances) {
			local t = {};
			t.town <- townBus.town;
			t.cargo <- townBus.cargo;
			t.stations <- townBus.stations;
			t.depot <- townBus.depot;
			t.isTransfer <- townBus.isTransfer;
			t.removeBus <- townBus.removeBus;
			array.push(t);
		}
		data.townBus <- array;
	}
	
	static function LoadStatics(data) {
		TownBus.instances.clear();
		foreach(t in data.townBus) {
			local townBus = TownBus(t.town, t.cargo);
			townBus.stations = t.stations;
			townBus.depot = t.depot;
			townBus.isTransfer = t.isTransfer;
			townBus.removeBus = t.removeBus;
			TownBus.instances.push(townBus);
		}
	}
	
	
	static function Check(tile, ignoreTileList=null, cargo = null) {
	/*
		if(AICompany.GetBankBalance(AICompany.COMPANY_SELF) < 200000) {
			return;
		}*/ //TODO busの採算性のチェック
		local authorityTown = AITile.GetTownAuthority (tile);
		if(!AITown.IsValidTown(authorityTown)) {
			return;
		}
		TownBus.CheckTown(authorityTown, ignoreTileList, cargo);
	}
	
	static function CheckTown(authorityTown, ignoreTileList=null, cargo = null) {
		//HgLog.Info("CheckTown:"+AITown.GetName(authorityTown));
		if(cargo == null || !AICargo.HasCargoClass(cargo, AICargo.CC_MAIL)) {
			cargo = HogeAI.GetPassengerCargo();
		}
		local key = authorityTown+":"+cargo;
		if(TownBus.townMap.rawin(key)) {
			return TownBus.townMap[key];
		}
		if(AIGroup.GetNumVehicles( AIGroup.GROUP_ALL, AIVehicle.VT_ROAD) >= RoadRoute.GetMaxTotalVehicles()) {
			return null;
		}
		local aiExec = AIExecMode();
		local townBus = TownBus(authorityTown, cargo);
		TownBus.instances.push(townBus);
		if(!townBus.BuildBusStops()) {
			return null;
		}
		return townBus;
	}
		
	town = null;
	cargo = null;
	stations = null;
	depot = null;
	isTransfer = null;
	removeBus = null;
	
	
	
	constructor(town, cargo) {
		this.town = town;
		this.cargo = cargo;
		this.stations = [];
		this.isTransfer = false;
		TownBus.townMap[town+":"+cargo] <- this;
	}
	
	function BuildBus() {
		if(!depot) {
			return false;
		}
	
		local currentBus = GetBus();
	
		local busEngine = ChooseBusEngine();
		if(busEngine == null) {
			HgLog.Warning("Not found bus engine "+this);
			return false;
		}
		HogeAI.WaitForPrice(AIEngine.GetPrice(busEngine));
		local bus = AIVehicle.BuildVehicle(depot, busEngine);
		if(!AIVehicle.IsValidVehicle(bus)) {
			HgLog.Warning("BuildBus failed "+this);
			return false;
		}
		AIVehicle.RefitVehicle(bus, cargo);
		if(AICargo.HasCargoClass(cargo, AICargo.CC_MAIL)) {
			AIVehicle.SetName(bus, "MailVan#"+AIVehicle.GetUnitNumber(bus));
		} else {
			AIVehicle.SetName(bus, "TownBus#"+AIVehicle.GetUnitNumber(bus));
		}

		if(currentBus != null) {
			AIOrder.ShareOrders(bus, currentBus);
		} else {
			AIOrder.AppendOrder(bus, stations[0], AIOrder.OF_NON_STOP_INTERMEDIATE);
			AIOrder.AppendOrder(bus, stations[1], AIOrder.OF_NON_STOP_INTERMEDIATE);
		}
		AIVehicle.StartStopVehicle(bus);
		return true;
	}
	
	function GetBus() {
		if(stations.len() != 2) {
			return null;
		}
		local list = AIVehicleList_Station(AIStation.GetStationID(stations[0]));
		local result = null;
		foreach(k,v in list) {
			local name = AIVehicle.GetName(k);
			if((name.find("TownBus") != null || name.find("MailVan") != null) && k != removeBus) {
				result = k;
				break;
			}
		}
		return result;
	}
	
	function ChangeTransferOrder(toPlatform, srcStation) {
		local bus = GetBus();
		AIOrder.RemoveOrder(bus,AIOrder.GetOrderCount(bus)-1);
		AIOrder.RemoveOrder(bus,AIOrder.GetOrderCount(bus)-1);
		AIOrder.AppendOrder(bus, srcStation, AIOrder.OF_NON_STOP_INTERMEDIATE | AIOrder.OF_FULL_LOAD_ANY);
		AIOrder.AppendOrder(bus, toPlatform, AIOrder.OF_NON_STOP_INTERMEDIATE | AIOrder.OF_TRANSFER | AIOrder.OF_NO_LOAD);
	}

	function ChooseBusEngine() {
		local engineSet = RoadRoute.EstimateEngineSet(RoadRoute, cargo, AIMap.DistanceManhattan(stations[0],stations[1]),  GetPlace().GetLastMonthProduction(cargo) / 2, true, true );
		return engineSet != null ? engineSet.engine : null;
	}
	
	
	function BuildBusStops() {
		local currentRoadType = AIRoad.GetCurrentRoadType();
		AIRoad.SetCurrentRoadType(GetRoadType()); // TODO tram対応
		local result = _BuildBusStops();
		AIRoad.SetCurrentRoadType(currentRoadType);
		return result;
	}
	
	function _BuildBusStops() {
	
		local aiTest = AITestMode();
		local tile = AITown.GetLocation(town);
		local rect = Rectangle.Center(HgTile(tile),5);
		 
		local tiles = HgArray.AIListKey(rect.GetTileList()).array;
		local stationA = FindStationTile(tiles);
		tiles.reverse();
		local stationB = FindStationTile(tiles);
		if(stationA != null && stationB != null && stationA[0] != stationB[0]) {
			local aiExec = AIExecMode();
			HogeAI.WaitForMoney(10000);
			local roadVehType = AICargo.HasCargoClass (cargo, AICargo.CC_PASSENGERS) ? AIRoad.ROADVEHTYPE_BUS : AIRoad.ROADVEHTYPE_TRUCK;
			if(!AIRoad.BuildDriveThroughRoadStation (stationA[0], stationA[1], roadVehType , AIStation.STATION_NEW)) {
				HgLog.Warning("failed BuildDriveThroughRoadStation"+HgTile(stationA[0])+" "+this);
				return false;
			}
			stations.push(stationA[0]);
			if(!AIRoad.BuildDriveThroughRoadStation (stationB[0], stationB[1], roadVehType , AIStation.STATION_NEW)) {
				HgLog.Warning("failed BuildDriveThroughRoadStation"+HgTile(stationB[0])+" "+this);
				return false;
			}
			stations.push(stationB[0]);
			return true;
		}
		return false;
	}
	
	function BuildBusDepot() {
		local currentRoadType = AIRoad.GetCurrentRoadType();
		AIRoad.SetCurrentRoadType(GetRoadType()); // TODO tram対応
		local result = _BuildBusDepot();
		AIRoad.SetCurrentRoadType(currentRoadType);
		return result;
	}
	
	function _BuildBusDepot() {
		local aiTest = AITestMode();
		local dirs = [AIMap.GetTileIndex(1, 0), AIMap.GetTileIndex(0, 1), AIMap.GetTileIndex(-1, 0), AIMap.GetTileIndex(0, -1)];
		for(local i=5; i<=15; i+=2) {
			local rect = Rectangle.Center(HgTile(AITown.GetLocation(town)),i);
			foreach(tile in HgArray.AIListKey(rect.GetTileList()).array) {
				if(!AIRoad.IsRoadTile(tile) || AITile.GetOwner(tile) != AICompany.COMPANY_INVALID) { 
					continue;
				}
				foreach(dir in dirs) {
					local depotTile = tile + dir;
					/*
					if(ignoreTileList.HasItem(depotTile)) {
						continue;
					}*/
					if(AIRoad.BuildRoadDepot (depotTile, tile)) {
						HgLog.Info("BuildBusDepot succeeded."+HgTile(depotTile)+" "+this);
						local aiExec = AIExecMode();
						HogeAI.WaitForMoney(10000);
						if(!AIRoad.AreRoadTilesConnected(tile, depotTile) && !AIRoad.BuildRoad(tile, depotTile)) {
							continue;
						}
						if(!AIRoad.BuildRoadDepot (depotTile, tile)) {
							HgLog.Warning("BuildBusDepot failed."+HgTile(depotTile)+" "+this);
							return false;
						}
						this.depot = depotTile;
						return true;
					}
				}
			}
		}
		HgLog.Warning("BuildBusDepot failed."+this);
		return false;
	}
	
	function FindStationTile(tiles) {
		local dirs = [AIMap.GetTileIndex(1, 0), AIMap.GetTileIndex(0, 1)];
		local radius = AIStation.GetCoverageRadius(AIStation.STATION_BUS_STOP);
		foreach(tile in tiles) {
			if(!AIRoad.IsRoadTile (tile) || AITile.GetCargoAcceptance(tile,cargo, 1, 1, radius) <= 8 || AITile.GetOwner(tile) != AICompany.COMPANY_INVALID) {
				continue;
			}
			foreach(dir in dirs) {
				if(AIRoad.BuildDriveThroughRoadStation (tile, tile + dir, AIRoad.ROADVEHTYPE_BUS , AIStation.STATION_NEW)) {
					return [tile,tile+dir];
				}
			}
			
		}
		
		return null;
	}
	
	function CreateTransferRoadRoute(number, srcStationTile, toHgStation, destRoute) {
		local depot = GetDepot();
		if(!depot) {
			HgLog.Warning("No depot(TownBus.CreateTransferRoadRoute)"+this);
			return false;
		}
		/*
		foreach(route in RoadRoute.instances) {
			if(route.srcHgStation.platformTile == srcStationTile) { //ルートの再利用
				if(!route.IsClosed()) {
					HgLog.Warning("TownBus.CreateTransferRoadRoute failed. Found Not closed route."+route+" "+this);
					return false;
				}
			
				route.destHgStation = toHgStation;
				route.destRoute = destRoute;
				route.ReOpen();
				HgLog.Info("Reuse route(TownBus.CreateTransferRoadRoute)"+route+" "+this);
				return true;
			}
		}*/
		local srcHgStation = null;
		foreach(station in GetPlace().GetStations()) {
			if(station.platformTile == srcStationTile) {
				srcHgStation = station;
			}
		}
		if(srcHgStation == null) {
			if(AICargo.HasCargoClass(cargo, AICargo.CC_MAIL)) {
				number = "M" + number;
			}
			srcHgStation = PieceStation(srcStationTile);
			srcHgStation.name = AITown.GetName(town)+" #"+number;
			srcHgStation.place = GetPlace();
			srcHgStation.cargo = cargo;
			srcHgStation.builded = true;
			srcHgStation.BuildExec();
		}
		local roadRoute = RoadRoute();
		roadRoute.cargo = cargo;
		roadRoute.srcHgStation = srcHgStation;
		roadRoute.destHgStation = toHgStation;
		roadRoute.isTransfer = true;
		roadRoute.destRoute = destRoute;
		roadRoute.depot = depot;
		roadRoute.useDepotOrder = false;
		roadRoute.Initialize();
		local vehicle = roadRoute.BuildVehicle();
		if(vehicle==null) {
			HgLog.Warning("BuildVehicle failed.(TownBus.CreateTransferRoadRoute)"+this);
			return false;
		}
		RoadRoute.instances.push(roadRoute);
		PlaceDictionary.Get().AddRoute(roadRoute);
		HgLog.Info("TownBus.CreateTransferRoadRoute succeeded."+this);
		return true;
	}
	
	function GetDepot() {
		if(depot == null) {
			if(!BuildBusDepot()) {
				depot = false;
			}
		}
		return depot;
	}
	
	function CheckInterval() {
		if(removeBus != null) {
			if(AIVehicle.IsStoppedInDepot(removeBus)) {
				AIVehicle.SellVehicle(removeBus);
				removeBus = null;
			}
		}
		if(stations.len()<2 || depot == false) {
			return;
		}
		if(depot == null) {
			if(GetDepot() != false) {
				if(!BuildBus()) {
					foreach(station in stations) {
						AIRoad.RemoveRoadStation(station);				
					}
					stations.clear();
					return;
				}
			} else {
				return;
			}
		}
		CheckTransfer();
		
		if(!isTransfer && AIBase.RandRange(100) < 5 && HogeAI.Get().IsRich()) {
			CheckRenewal();
		}
	}

	function CheckRenewal() {
		local bus = GetBus();
		local aiExec = AIExecMode();
		if(bus == null || removeBus != null) {
			return;
		}
		local engine = ChooseBusEngine();
		if(engine != AIVehicle.GetEngineType(bus) || AIVehicle.GetAgeLeft(bus) <= 600) {
			if(BuildBus()) {
				if((AIOrder.OF_STOP_IN_DEPOT & AIOrder.GetOrderFlags(bus, AIOrder.ORDER_CURRENT)) == 0) {
					AIVehicle.SendVehicleToDepot (bus);
				}
				removeBus = bus;
			}
		}
	}
	
	function GetPlace() {
		return TownCargo(town, cargo, true);
	}
		
	function GetTownRoutes() {
		local result = [];
		local usedRoutes = PlaceDictionary.Get().GetRoutesBySource(GetPlace());
		foreach(usedRoute in usedRoutes) {
			foreach(station in stations) {
				if(usedRoute.srcHgStation.platformTile == station) {
					result.push(usedRoute);
				}
			}
		}
		return result;
	}

	function IsAllTownRoutesClosed() {
		foreach(townRoute in GetTownRoutes()) {
			if(!townRoute.IsClosed()/* && !townRoute.IsOverflowPlace(GetPlace())*/) {
				return false;
			}
		}
		return true;
	}

	function CheckTransfer() {
		
		if(isTransfer) {
			if(IsAllTownRoutesClosed()) {
				HgLog.Info("ChangeTransferToTownBus(IsAllTownRoutesClosed or Overflow):"+this);
				if(BuildBus()) {
					isTransfer = false;
				}
			} else {
				//HgLog.Info("Not closed or overflow:"+this);
			}
		}

		/*
		if(stations.len() < 2 ) {
			return;
		}
		
		
		local place = GetPlace();
		foreach(route in PlaceDictionary.Get().GetRoutesBySource(place)) {
			local placeStation = route.srcHgStation.place.IsSamePlace(place) ? route.srcHgStation : route.destHgStation;
			if(	Place.IsNgPathFindPair(stations[0], placeStation, AIVehicle.VT_ROAD) ) {
				continue;
			}
			if(route.IsClosed() || !route.NeedsAdditionalProducingPlace(place)) {
				continue;
			}
			if(route.srcHgStation.GetName().find("#")) {
				continue;
			}
			if(route.cargo != cargo) {
				continue;
			}
			
			local toHgStation = null;
			foreach(station in placeStation.stationGroup.hgStations) {
				if((station instanceof PieceStation || station instanceof RoadStation) && station.cargo == cargo) {
					if(AIRoad.HasRoadType(station.platformTile, GetRoadType())) {
						toHgStation = station;
						break;
					}
				}
			}
			local currentRoadType = AIRoad.GetCurrentRoadType();
			AIRoad.SetCurrentRoadType(GetRoadType());
			Place.AddNgPathFindPair(stations[0], placeStation, AIVehicle.VT_ROAD); // 一度transferした所に再度transferしない。(失敗しても何度もリトライする可能性があるので)
			if(toHgStation == null) {
				local stationFactory = RoadStationFactory(AICargo.HasCargoClass(cargo,AICargo.CC_PASSENGERS) ? AIStation.STATION_BUS_STOP : AIStation.STATION_TRUCK_STOP);
				toHgStation = stationFactory.CreateBestOnStationGroup( placeStation.stationGroup, cargo, GetPlace().GetLocation() );
				
				local execMode = AIExecMode();
				if(toHgStation == null || !toHgStation.BuildExec()) {
					HgLog.Warning("Not found PieceStation and RoadStation and BuildStation failed:"+route+" at "+this);
					AIRoad.SetCurrentRoadType(currentRoadType);
					continue;
				}
			}
			HgLog.Info("CreateTransfer:"+this+" (used route:"+route+")");
			
			removeBus = GetBus();
			if(removeBus != null) {
				if((AIOrder.OF_STOP_IN_DEPOT & AIOrder.GetOrderFlags(removeBus, AIOrder.ORDER_CURRENT)) == 0) {
					AIVehicle.SendVehicleToDepot (removeBus);
				}
			}
			
			
			if(RoadBuilder().BuildPath([stations[0]], [toHgStation.platformTile], true)) {
				CreateTransferRoadRoute(1, stations[0], toHgStation, route);
			}
			if(RoadBuilder().BuildPath([stations[1]], [toHgStation.platformTile], true)) {
				CreateTransferRoadRoute(2, stations[1], toHgStation, route);
			}
			isTransfer = true;

			AIRoad.SetCurrentRoadType(currentRoadType);
		}*/
		
	}

	function CreateTransferRoutes(route, placeStation) {
		HogeAI.Get().supressInterval = true; // TownBus.CheckIntervalとの競合を防ぐ
		_CreateTransferRoutes(route, placeStation);
		HogeAI.Get().supressInterval = false;
	}

	
	function _CreateTransferRoutes(route, placeStation) {
		if(stations.len() < 2 ) {
			return;
		}
		
		local currentRoadType = AIRoad.GetCurrentRoadType();
		
		local toHgStation = null;
		foreach(station in placeStation.stationGroup.hgStations) {
			if((station instanceof PieceStation || station instanceof RoadStation) && station.cargo == cargo && station != placeStation) {
				if(AIRoad.HasRoadType(station.platformTile, GetRoadType())) {
					toHgStation = station;
					break;
				}
			}
		}
		AIRoad.SetCurrentRoadType(GetRoadType());
		if(toHgStation == null) {
			toHgStation = RoadStationFactory(cargo).CreateBestOnStationGroup( placeStation.stationGroup, cargo, GetPlace().GetLocation() );
			if(toHgStation == null) {
				toHgStation = RoadStationFactory(cargo,true/*isPieceStation*/).CreateBestOnStationGroup( placeStation.stationGroup, cargo, GetPlace().GetLocation() );
			}
			
			local execMode = AIExecMode();
			if(toHgStation == null || !toHgStation.BuildExec()) {
				HgLog.Warning("Not found PieceStation and RoadStation and BuildStation failed:"+route+" at "+this);
				AIRoad.SetCurrentRoadType(currentRoadType);
				return;
			}
		}
		HgLog.Info("CreateTransfer:"+this+" (used route:"+route+")");
		
		removeBus = GetBus();
		if(removeBus != null) {
			if((AIOrder.OF_STOP_IN_DEPOT & AIOrder.GetOrderFlags(removeBus, AIOrder.ORDER_CURRENT)) == 0) {
				AIVehicle.SendVehicleToDepot (removeBus);
			}
		}
		
		
		if(RoadBuilder().BuildPath([stations[0]], [toHgStation.platformTile], true)) {
			CreateTransferRoadRoute(1, stations[0], toHgStation, route);
		}
		if(RoadBuilder().BuildPath([stations[1]], [toHgStation.platformTile], true)) {
			CreateTransferRoadRoute(2, stations[1], toHgStation, route);
		}
		isTransfer = true;

		AIRoad.SetCurrentRoadType(currentRoadType);
	}
	
	function GetRoadType() {
		return AIRoadTypeList(AIRoad.ROADTRAMTYPES_ROAD).Begin();	
	}
	
	
	function _tostring() {
		return "TownBus["+AITown.GetName(town)+":"+AICargo.GetName(cargo)+"]";
	}
}
