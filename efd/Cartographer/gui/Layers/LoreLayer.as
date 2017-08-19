﻿// Copyright 2017, Earthfiredrake (Peloprata)
// Released under the terms of the MIT License
// https://github.com/Earthfiredrake/TSW-Cartographer

import flash.geom.Point;

import com.GameInterface.Lore;

import efd.Cartographer.lib.etu.MovieClipHelper;
import efd.Cartographer.lib.Mod;

import efd.Cartographer.Waypoints.LorePoint;

import efd.Cartographer.gui.NotationLayer;
import efd.Cartographer.gui.WaypointIcon;

class efd.Cartographer.gui.Layers.LoreLayer extends NotationLayer {
	public static var __className:String = "efd.Cartographer.gui.Layers.LoreLayer";

	private function LoreLayer() {
		super();
		createEmptyMovieClip("ClaimedLoreSublayer", getNextHighestDepth());
		createEmptyMovieClip("UnclaimedLoreSublayer", getNextHighestDepth());
		RenderedClaimedWaypoints = new Array();
		RenderedUnclaimedWaypoints = new Array();
		Lore.SignalTagAdded.Connect(LorePickedUp, this);
	}

	public function RenderWaypoints(newZone:Number):Void {
		ClaimedCount = 0;
		UnclaimedCount = 0;
		super.RenderWaypoints(newZone);
	}

	private function AttachWaypoint(data:LorePoint, mapPos:Point):Void {
		var claim:String = Lore.IsLocked(data.LoreID) ? "Unclaimed" : "Claimed";
		var existing:WaypointIcon = this["Rendered" + claim + "Waypoints"][this[claim + "Count"]];
		this[claim + "Count"] += 1;
		if (existing) {
			existing.Reassign(data, mapPos);
		} else {
			var targetClip:MovieClip = this[claim + "LoreSublayer"];
			var wp:WaypointIcon = WaypointIcon(MovieClipHelper.createMovieWithClass(WaypointIcon, "WP" + targetClip.getNextHighestDepth(), targetClip, targetClip.getNextHighestDepth(), {Data : data, _x : mapPos.x, _y : mapPos.y}));
			wp.SignalWaypointLoaded.Connect(LoadSequential, this);
			wp.LoadIcon();
			this["Rendered" + claim + "Waypoints"].push(wp);
		}
	}

	private function ClearDisplay(partialClear:Number):Void {
		if (partialClear == undefined) {
			ClaimedCount = 0;
			UnclaimedCount = 0;
		}
		for (var i:Number = ClaimedCount; i < RenderedClaimedWaypoints.length; ++i) {
			var waypoint:MovieClip = RenderedClaimedWaypoints[i];
			waypoint.Unload();
			waypoint.removeMovieClip();
		}
		RenderedClaimedWaypoints.splice(ClaimedCount);
		for (var i:Number = UnclaimedCount; i < RenderedUnclaimedWaypoints.length; ++i) {
			var waypoint:MovieClip = RenderedUnclaimedWaypoints[i];
			waypoint.Unload();
			waypoint.removeMovieClip();
		}
		RenderedUnclaimedWaypoints.splice(UnclaimedCount);
	}

	// First param appears to be tagID (loreID)
	// Second param has value 50000:16779181 on both tested values (unsure what info this is just yet)
	private function LorePickedUp(loreID:Number):Void {
		if (Lore.GetTagType(loreID) == _global.Enums.LoreNodeType.e_Lore) {
			Mod.TraceMsg("Lore Picked Up!");
			var matches:Number = 0;
			for (var i:Number = 0; i < RenderedUnclaimedWaypoints.length; ++i) {
				// Front load all the matching waypoints
				if (RenderedUnclaimedWaypoints[i].Data.LoreID == loreID) {
					var temp:WaypointIcon = RenderedUnclaimedWaypoints[matches];
					RenderedUnclaimedWaypoints[matches] = RenderedUnclaimedWaypoints[i];
					RenderedUnclaimedWaypoints[i] = temp;
					matches += 1;
				}
			}
		} else {
			Mod.TraceMsg("Logic Failure?");
		}
	}

	public function get RenderedWaypoints():Array {
		return RenderedClaimedWaypoints.concat(RenderedUnclaimedWaypoints);
	}

	private var ClaimedLoreSublayer:MovieClip;
	private var UnclaimedLoreSublayer:MovieClip;

	private var ClaimedCount:Number;
	private var UnclaimedCount:Number;

	private var RenderedClaimedWaypoints:Array;
	private var RenderedUnclaimedWaypoints:Array;
}
