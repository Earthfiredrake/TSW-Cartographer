﻿// Copyright 2017, Earthfiredrake (Peloprata)
// Released under the terms of the MIT License
// https://github.com/Earthfiredrake/TSW-Cartographer

import gfx.utils.Delegate;

import efd.Cartographer.lib.ConfigWrapper;
import efd.Cartographer.lib.LocaleManager;
import efd.Cartographer.lib.Mod;
import efd.Cartographer.Waypoint;

class efd.Cartographer.Cartographer extends Mod {
	private static var ModInfo:Object = {
		// Debug settings at top so that commenting out leaves no hanging ','
		//Trace : true,
		GuiFlags : ef_ModGui_NoConfigWindow,
		Name : "Cartographer",
		Version : "0.0.2.alpha"
	};

	/// Initialization
	public function Cartographer(hostMovie:MovieClip) {
		super(ModInfo, hostMovie);
		// Ingame debug menu registers variables that are initialized here, but not those initialized at class scope

		InitializeConfig();

		Waypoints = new Object();
		LoadWaypoints();

		TraceMsg("Initialized");
	}

	private function InitializeConfig(arConfig:ConfigWrapper):Void {
	}

	private function LoadWaypoints():Void {
		FileLoader = new XML();
		FileLoader.ignoreWhite = true;
		FileLoader.onLoad = Delegate.create(this, ParseWaypoints);
		FileLoader.load("Cartographer\\waypoints\\BasePack.xml");
	}

	private function ParseWaypoints(success:Boolean):Void {
		if (success) {
			var xmlRoot:XMLNode = FileLoader.firstChild;
			for (var i:Number = 0; i < xmlRoot.childNodes.length; ++i) {
				var zone:XMLNode = xmlRoot.childNodes[i];
				if (Waypoints[zone.attributes.id] == undefined) {
					Waypoints[zone.attributes.id] = new Array();
				}
				for (var j:Number = 0; j < zone.childNodes.length; ++j) {
					var category:XMLNode = zone.childNodes[j];
					for (var k:Number = 0; k < category.childNodes.length; ++k) {
						Waypoints[zone.attributes.id].push(new Waypoint(category.childNodes[k], category.attributes.icon));
					}
				}
			}
			delete FileLoader;
			TraceMsg("Waypoints loaded");
		} else {
			ErrorMsg("Unable to load waypoint file");
		}
	}

	/// Mod framework extensions and overrides
	private function ConfigChanged(setting:String, newValue, oldValue):Void {
		switch(setting) {
			default:
				super.ConfigChanged(setting, newValue, oldValue);
				break;
		}
	}

	private function DoUpdate(newVersion:String, oldVersion:String):Void {
		// Version specific updates
		//   Some upgrades may reflect unreleased builds, for consistency on develop branch
	}

	private function Activate():Void {
	}

	private function Deactivate():Void {
	}

	private function InterfaceWindowLoaded():Void {
		TraceMsg("Opening interface window");
		InterfaceWindowClip.m_Content.SetWaypoints(Waypoints);
	}

	/// Variables
	private var FileLoader:XML;
	private var Waypoints:Object; // Multi level array/map (Zone->Layer/Type->WaypointData) Note: Layer/Type not yet in use
}
