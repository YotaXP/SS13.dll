/*
	These are simple defaults for your project.
 */

world
	icon_size = 32	// 32x32 icon size by default

	maxx = 15
	maxy = 15
	maxz = 1
	view = 7

//#define SS13_DLL	"SS13.dll"
#define SS13_DLL	"CopySS13.dll"
//#define SS13_DLL	"C:\\Users\\yotax\\Desktop\\SS13 DLL\\SS13 DLL\\Debug\\SS13.dll"

#define dll_GetDebugLog				call(SS13_DLL, "GetDebugLog")
#define dll_Atmos_Initialize		call(SS13_DLL, "Atmos_Initialize")
#define dll_Atmos_GetInfo			call(SS13_DLL, "Atmos_GetInfo")
#define dll_Atmos_RunCycle			call(SS13_DLL, "Atmos_RunCycle")
#define dll_Atmos_GetHazardUpdates	call(SS13_DLL, "Atmos_GetHazardUpdates")
#define dll_Atmos_GetGasses			call(SS13_DLL, "Atmos_GetGasses")

#define DllSuccess(X)	(text2ascii((X), 1) != 0x15)
//#define DllSuccess(X)	(text2ascii((X), 1) == 0x06)
//#define DllFail(X)		(text2ascii((X), 1) == 0x15)
#define DllGetError(X)	(copytext((X), 2))

var/iterationsPerHalfSecond = 0

world
	New()
		..()
		//fcopy("C:\\Users\\yotax\\Desktop\\SS13 DLL\\SS13 DLL\\Debug\\SS13.dll", "SS13.dll")
		fcopy("SS13.dll", "CopySS13.dll")
		var/ret = dll_Atmos_Initialize("[world.maxx]", "[world.maxy]", "0")
		//var/ret = dll_Atmos_Initialize("512", "512", "1")
		if(!DllSuccess(ret))
			spawn(10) world << DllGetError(ret)
		else
			for(var/turf/T in world)
				T.UpdateShade()

		spawn(10) while(1)
			ret = dll_GetDebugLog()
			if(DllSuccess(ret))
				if(ret)
					world << "<span class='dlldebug'>" + ret
			else
				world << "<span class='dlldebug'>Failed to get DLL debug log: " + DllGetError(ret)
			sleep(2)

		spawn(10) while(1)
			if(iterationsPerHalfSecond > 0)
				RunAtmosCycle(iterationsPerHalfSecond)
			sleep(5)

proc/PrintAtmosInfo()
	//var/ret = dll_Atmos_GetInfo()
	//if(DllSuccess(ret))
	//	var/list/info = params2list(ret)
	//	world << "Iterations: [info["iterations"]]"

proc/RunAtmosCycle(iterations)
	var/ret = dll_Atmos_RunCycle("[iterations]")
	if(!DllSuccess(ret))
		world << DllGetError(ret)
		return

	ret = dll_Atmos_GetHazardUpdates()
	if(!DllSuccess(ret))
		world << DllGetError(ret)
		return

	var/list/changes = params2list(ret)
	for(var/coord in changes)
		var/comma = findtextEx(coord, ",")
		if(!comma) throw EXCEPTION("NO COMMA?!")
		var/x = text2num(copytext(coord, 1, comma))
		var/y = text2num(copytext(coord, comma + 1))
		var/turf/T = locate(x, y, 1)
		if(!T) continue //throw EXCEPTION("NO TURF?!") // Exception disabled since I commonly test with a larger atmos grid than turf grid.
		T.overlays.Cut()
		var/hazards = changes[coord]
		if(findtextEx(hazards, "f")) T.overlays += "fire"
		if(findtextEx(hazards, "p")) T.overlays += "plasma"
		if(findtextEx(hazards, "n")) T.overlays += "n2o"

	for(var/turf/T in world)
		T.UpdateShade()
	PrintAtmosInfo()

turf
	icon = 'Test.dmi'

	var
		obj/airflow
			afNorth
			afEast

	New()
		..()
		afNorth = new(src)
		afEast = new(src)
		afNorth.pixel_y = 16
		afEast.pixel_x = 16

	icon_state = "floor"

	proc
		UpdateShade()
			var/ret = dll_Atmos_GetGasses("[x]", "[y]")
			if(DllSuccess(ret))
				//var/list/gas = JSON.parse(ret)
				//var/pressure = gas["pressure"]
				//var/temperature = gas["temperature"]
				//var/o2 = 0 + gas["moles"]["O2"]
				//var/plasma = 0 + gas["moles"]["Pl"]
				//var/tMoles = max(0.01, gas["totalMoles"])
				//var/velX = 0 + gas["velocity"][1]
				//var/velY = 0 + gas["velocity"][2]

				var/list/gas = params2list(ret)
				var/pressure = text2num(gas["pressure"])
				var/temperature = text2num(gas["temperature"])
				var/o2 = text2num(gas["O2"])
				var/plasma = text2num(gas["Pl"])
				var/tMoles = max(0.01, text2num(gas["moles"]))
				var/velX = text2num(gas["velX"])
				var/velY = text2num(gas["velY"])
				color = rgb(plasma*40/25, pressure/*temperature*/, o2*400/25)
				name = "Pressure: [round(pressure, 0.1)]kPa  O2: [round(o2/tMoles*100, 0.1)]%  Plasma: [round(plasma/tMoles*100, 0.1)]%  " \
				     + "Temp: [round(temperature, 0.01)]K  Velocity: [round(velX, 0.01)],[round(velY, 0.01)]"
				var/matrix/M = matrix()
				var/scale = velY * pressure / 100;
				M.Scale(scale, scale * 2)
				afNorth.transform = M
				M = matrix()
				M.Turn(90)
				scale = velX * pressure / 100;
				M.Scale(scale * 2, scale)
				afEast.transform = M
			else
				color = "#FF0000"

obj
	icon = 'Test.dmi'
	mouse_opacity = 0

	airflow
		icon_state = "arrow"
	wall
		icon_state = "wall"
	staticg
		icon_state = "static"
	overlay
		icon_state = "overlay"
		screen_loc = "WEST,SOUTH to EAST,NORTH"

client
	var
		drawMode = "air"
		drawAirInfo = list("pressure"=0, "temperature"=20)
		iterationsPerCycle = 1

	MouseDown(turf/object, location, control, params)
		.=..()
		var/list/p = params2list(params)
		while(!isnull(object) && !isturf(object))
			object = object.loc
		if(p["left"] && istype(object))
			if(!drawAirInfo) return
			var/ret = call(SS13_DLL, "Atmos_SetTileGasses")("[object.x]", "[object.y]", list2params(drawAirInfo))
			if(!DllSuccess(ret))
				world << DllGetError(ret)
			else
				object.UpdateShade()

			switch(drawMode)
				if("wall")
					new/obj/wall{dir=4}(object)
					new/obj/wall{dir=1}(object)
					new/obj/wall{dir=8}(object)
					new/obj/wall{dir=2}(object)
				if("wallE")
					new/obj/wall{dir=4}(object)
				if("wallN")
					new/obj/wall{dir=1}(object)
				if("wallW")
					new/obj/wall{dir=8}(object)
				if("wallS")
					new/obj/wall{dir=2}(object)
				if("floor")
					for(var/obj/wall/O in object) del O
				if("static")
					new/obj/staticg(object)
				if("variable")
					for(var/obj/staticg/O in object) del O
	MouseDrag(src_object,turf/object,src_location,over_location,src_control,over_control,params)
		.=..()
		MouseDown(object, over_location, over_control, params)

	Click(turf/object, location, control, params)
		.=..()
		var/list/p = params2list(params)
		while(!isnull(object) && !isturf(object))
			object = object.loc
		if(p["middle"] && istype(object))
			var/ret = dll_Atmos_GetGasses("[object.x]", "[object.y]")
			if(DllSuccess(ret))
				//ret = JSON.parse(ret)
				ret = params2list(ret)
				var_dump(ret)
			else
				world << DllGetError(ret)


	New()
		..()
		world << "<b>[key] logged in."
		screen += new/obj/overlay
	Del()
		world << "<b>[key] logged out."
		..()

	verb
		Say(msg as text)
			set category = "Misc"
			world << "<b>[key]</b>: [msg]"
		Who()
			set category = "Misc"
			src << "------"
			for(var/client/C) src << C.key
		Reboot()
			set category = "Misc"
			world << "<b>Rebooted by [key]"
			world.Reboot()

		Airflow_Arrows_Show()
			set category = "Simulation"
			for(var/obj/airflow/O) O.invisibility = 0
		Airflow_Arrows_Hide()
			set category = "Simulation"
			for(var/obj/airflow/O) O.invisibility = 101
		Run_Cycle()
			set category = "Simulation"
			RunAtmosCycle(iterationsPerCycle)
		SetIterations_Per_Cycle(iter as num)
			set category = "Simulation"
			iterationsPerCycle = min(max(iter, 1), 10)
		Set_Iterations_Per_Half_Second(iter as num)
			set category = "Simulation"
			iterationsPerHalfSecond = min(max(iter, 0), 5)
			world << "Automatic iterations per 0.5 seconds set to: [iterationsPerHalfSecond]"
		Fill_With_Current_Brush()
			set category = "Paint"
			var/ret = call(SS13_DLL, "Atmos_SetAllTileGasses")(list2params(drawAirInfo))
			if(!DllSuccess(ret))
				world << DllGetError(ret)
			else
				for(var/turf/T in world)
					T.UpdateShade()
					switch(drawMode)
						if("wall")
							new/obj/wall{dir=4}(T)
							new/obj/wall{dir=1}(T)
							new/obj/wall{dir=8}(T)
							new/obj/wall{dir=2}(T)
						if("wallE")
							new/obj/wall{dir=4}(T)
						if("wallN")
							new/obj/wall{dir=1}(T)
						if("wallW")
							new/obj/wall{dir=8}(T)
						if("wallS")
							new/obj/wall{dir=2}(T)
						if("floor")
							for(var/obj/wall/O in T) del O
						if("static")
							new/obj/staticg(T)
						if("variable")
							for(var/obj/staticg/O in T) del O

		Paint_Air_Empty()
			set category = "Paint"
			drawMode = "air"
			drawAirInfo = list("pressure"=0, "temperature"=20)
		Paint_Air_Normal()
			set category = "Paint"
			drawMode = "air"
			drawAirInfo = list("pressure"=1, "temperature"=20, "O2"=0.21, "N"=0.79)
		Paint_Air_High_Pressure()
			set category = "Paint"
			drawMode = "air"
			drawAirInfo = list("pressure"=40, "temperature"=20, "O2"=0.21, "N"=0.79)
		Paint_Air_Plasma()
			set category = "Paint"
			drawMode = "air"
			drawAirInfo = list("pressure"=5, "temperature"=20, "Pl"=1)
		Paint_Hot_Burn_Mix()
			set category = "Paint"
			drawMode = "air"
			drawAirInfo = list("pressure"=2, "temperature"=150, "Pl"=1, "O2"=10)
		Paint_Air_Custom()
			set category = "Paint"
			var/airInfo = list()
			var/i = input("Pressure (in bars)", "Custom Air", 0 + drawAirInfo["pressure"]) as num|null
			if(isnull(i)) return;
			airInfo["pressure"] = i
			i = input("Temperature (in celcius)", "Custom Air", 0 + drawAirInfo["temperature"]) as num|null
			if(isnull(i)) return;
			airInfo["temperature"] = i
			i = input("Oxygen Ratio", "Custom Air", 0 + drawAirInfo["O2"]) as num|null
			if(isnull(i)) return;
			airInfo["O2"] = i
			i = input("Nitrogen Ratio", "Custom Air", 0 + drawAirInfo["N"]) as num|null
			if(isnull(i)) return;
			airInfo["N"] = i
			i = input("Plasma Ratio", "Custom Air", 0 + drawAirInfo["Pl"]) as num|null
			if(isnull(i)) return;
			airInfo["Pl"] = i
			i = input("Carbon Dioxide Ratio", "Custom Air", 0 + drawAirInfo["CO2"]) as num|null
			if(isnull(i)) return;
			airInfo["CO2"] = i
			drawMode = "air"
			drawAirInfo = airInfo

		Paint_Block_East()
			set category = "Paint"
			drawMode = "wallE"
			drawAirInfo = list("blockE"=1)
		Paint_Block_North()
			set category = "Paint"
			drawMode = "wallN"
			drawAirInfo = list("blockN"=1)
		Paint_Block_West()
			set category = "Paint"
			drawMode = "wallW"
			drawAirInfo = list("blockW"=1)
		Paint_Block_South()
			set category = "Paint"
			drawMode = "wallS"
			drawAirInfo = list("blockS"=1)
		Paint_Block_Full()
			set category = "Paint"
			drawMode = "wall"
			drawAirInfo = list("blockE"=1, "blockN"=1, "blockW"=1, "blockS"=1)
		Paint_Block_Remove()
			set category = "Paint"
			drawMode = "floor"
			drawAirInfo = list("blockE"=-1, "blockN"=-1, "blockW"=-1, "blockS"=-1)

		Paint_Mark_Static()
			set category = "Paint"
			drawMode = "static"
			drawAirInfo = list("static"=1)
		Paint_Mark_Variable()
			set category = "Paint"
			drawMode = "variable"
			drawAirInfo = list("static"=-1)

