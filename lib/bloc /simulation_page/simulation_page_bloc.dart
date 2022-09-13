import 'dart:async';
import 'dart:ui';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:open_bsp/model/debugging_offset.dart';
import 'package:open_bsp/model/simulation/simulation_result/collision_result.dart';
import 'package:open_bsp/model/simulation/simulation_result/simulation_tool_result.dart';
import 'package:open_bsp/pages/simulation_page/ticker.dart';
import 'package:open_bsp/model/simulation/tool_type.dart';
import 'package:open_bsp/services/geometric_calculations_service.dart';

import 'package:collection/collection.dart';

import '../../model/line.dart';
import '../../model/simulation/simulation_result/bend_result.dart';
import '../../model/simulation/tool.dart';
import '../../model/simulation/enums/tool_category_enum.dart';

part 'simulation_page_event.dart';

part 'simulation_page_state.dart';

/// Business logic for the [SimulationPage].
class SimulationPageBloc
    extends Bloc<SimulationPageEvent, SimulationPageState> {
  SimulationPageBloc({required Ticker ticker})
      : _ticker = ticker,
        super(SimulationPageInitial(
          tools: [],
          lines: [],
          selectedBeams: [],
          selectedTracks: [],
          selectedPlates: [],
          bendingHistory: [],
          simulationResult: [],
          rotationAngle: 0,
          debugOffsets: [],
          collisionOffsets: [],
          inCollision: false,
          isSimulationRunning: false,
          duration: 0,
          currentTick: 9999,
        )) {
    on<SimulationPageCreated>(_setInitialLines);
    on<SimulationToolsChanged>(_setTools);
    on<SimulationToolRotate>(_rotateTool);
    on<SimulationSelectedPlateLineChanged>(_nextLineOfPlate);
    on<SimulationToolMirrored>(_onMirrorTool);
    on<SimulationCollisionDetected>(_onCollisionDetect);
    on<SimulationStarted>(_onSimulationStart);
    on<SimulationStopped>(_onSimulationStopped);
    on<SimulationTicked>(_onTicked);
    on<SimulationPlateUnbended>(_onUnbendPlate2);
    on<SimulationPlateBended>(_onBendPlate);

    // fakeStream.listen((_) {
    //   print('fakestream');
    //   add(SimulationTicked());
    // });
  }

  GeometricCalculationsService _calculationsService =
      new GeometricCalculationsService();

  List<Offset> collisionOffsets = [];

  final Ticker _ticker;
  StreamSubscription<int>? _streamSubscription;

  // StreamController<int> fakeStream = StreamController<int>.broadcast();

  // var fakeStream =
  //     Stream<int>.periodic(const Duration(seconds: 1), (x) => x).take(15);

  Timer? _timer;

  /// Set the initial lines of the simulation.
  void _setInitialLines(
      SimulationPageCreated event, Emitter<SimulationPageState> emit) {
    emit(state.copyWith(lines: event.lines));
  }

  /// Set the tools of the simulation.
  /// This method is called when the [SimulationToolsChanged] event is emitted.
  void _setTools(
      SimulationToolsChanged event, Emitter<SimulationPageState> emit) {
    if (event.tools.isEmpty) return;

    List<Tool> selectedBeams =
        _getToolsByCategory(event.tools, ToolCategoryEnum.BEAM);
    List<Tool> selectedTracks =
        _getToolsByCategory(event.tools, ToolCategoryEnum.TRACK);
    List<Tool> selectedPlates =
        _getToolsByCategory(event.tools, ToolCategoryEnum.PLATE_PROFILE);

    _placeLowerBeam(selectedBeams, event, emit);
    _placeLowerTrackOnLowerBeam(event, selectedTracks, emit);

    _placePlateOnLowerTrack(event, emit, selectedPlates);

    _placeUpperTrackOnPlate2(event, emit, selectedTracks);
    _placeUpperBeamOnUpperTack2(event, emit, selectedTracks, selectedBeams);

    // emit(state
    //     .copyWith(selectedBeams: [], selectedTracks: [], selectedPlates: []));
    // emit(state.copyWith(
    //   selectedBeams: selectedBeams,
    //   selectedTracks: selectedTracks,
    //   selectedPlates: selectedPlates,
    // ));
  }

  /// Places the lower beam in the simulation.
  /// This method is called when the [SimulationBeamsChanged] event is emitted.
  void _placeLowerBeam(List<Tool> selectedBeams, SimulationToolsChanged event,
      Emitter<SimulationPageState> emit) {
    Tool lowerBeam = selectedBeams
        .firstWhere((beam) => beam.type.type == ToolType.lowerBeam);

    emit(state.copyWith(
      selectedBeams: [],
    ));
    emit(state.copyWith(
      selectedBeams: [lowerBeam],
    ));
  }

  /// Place a track on a beam.
  /// This method is called when the [SimulationToolsChanged] event is emitted.
  /// The track is placed on the beam at the same position as the beam.
  Tool _placeTrackOnBeam(Tool track, Tool beam) {
    print('placeTrackOnBeam');

    Line beamAdapterLine = beam.lines.where((line) => line.isSelected).first;
    Line trackAdapterLine = track.lines.where((line) => line.isSelected).first;

    Offset beamOffset;
    Offset trackOffset;

    beamAdapterLine.start.dy > beamAdapterLine.end.dy
        ? beamOffset = beamAdapterLine.start
        : beamOffset = beamAdapterLine.end;

    trackAdapterLine.start.dy > trackAdapterLine.end.dy
        ? trackOffset = trackAdapterLine.start
        : trackOffset = trackAdapterLine.end;

    Offset newOffset = beamOffset - trackOffset;

    Tool newTool = _moveTool(track, newOffset, true);

    return newTool;
  }

  /// Place the plate on the track with the next edge.
  void _nextLineOfPlate(SimulationSelectedPlateLineChanged event,
      Emitter<SimulationPageState> emit) {
    Tool plate = state.selectedPlates.first;

    _selectNextLineOfPlateAndPlace(plate, emit);
  }

  /// TODO
  void _selectNextLineOfPlateAndPlace(
      Tool plate, Emitter<SimulationPageState> emit) {
    List<Line> lines = plate.lines;
    Line? currentlyPlacedLine =
        lines.firstWhereOrNull((line) => line.isSelected) ?? lines.first;

    int index = plate.lines.indexOf(currentlyPlacedLine);
    lines[index].isSelected = false;

    index < lines.length - 1
        ? lines[index + 1].isSelected = true
        : lines.first.isSelected = true;

    plate = plate.copyWith(lines: lines);
    plate = _rotateUntilSelectedLineHasAngle(plate, [0, 360], 1);

    Tool lowerTrack = state.selectedTracks
        .firstWhere((tool) => tool.type.type == ToolType.lowerTrack);

    Tool placedPlate = _placePlateOnTrack(emit, plate, lowerTrack);

    emit(state.copyWith(selectedPlates: []));
    emit(state.copyWith(selectedPlates: [placedPlate]));
  }

  /// Place plate on lower track.
  Tool _placePlateOnTrack(
      Emitter<SimulationPageState> emit, Tool plate, Tool lowerTrack) {
    List<Offset> trackOffsets =
        lowerTrack.lines.map((line) => line.start).toList() +
            lowerTrack.lines.map((line) => line.end).toList();

    Line? selectedLine =
        plate.lines.firstWhereOrNull((line) => line.isSelected) ??
            plate.lines.first;

    List<Offset> lowestTrackXOffsets =
        _calculationsService.getLowestX(trackOffsets);

    Offset trackOffset =
        _calculationsService.getLowestY(lowestTrackXOffsets).first;

    Offset plateOffset = _calculationsService
        .getLowestX([selectedLine.start, selectedLine.end]).first;

    plateOffset = new Offset(plateOffset.dx, plateOffset.dy + (plate.s / 2));

    Offset moveOffset = plateOffset - trackOffset;

    Tool movedTool = _moveTool(plate, moveOffset, false);

    return movedTool;
  }

  /// Move a tool.
  /// The tool is moved by the given [offset].
  Tool _moveTool(Tool tool, Offset offset, bool positiveDirection) {
    List<Line> lines = tool.lines;
    List<Line> newLines = [];
    lines.forEach((line) {
      if (positiveDirection) {
        newLines.add(
            line.copyWith(start: line.start + offset, end: line.end + offset));
      } else {
        newLines.add(
            line.copyWith(start: line.start - offset, end: line.end - offset));
      }
    });

    return tool.copyWith(lines: newLines);
  }

  Line _moveLine(Line line, Offset offset, bool positiveDirection) {
    if (positiveDirection) {
      return line.copyWith(start: line.start + offset, end: line.end + offset);
    } else {
      return line.copyWith(start: line.start - offset, end: line.end - offset);
    }
  }

  List<Tool> _getToolsByCategory(List<Tool> tools, ToolCategoryEnum category) {
    return tools.where((tool) => tool.type.category == category).toList();
  }

  Tool? _getToolByType(List<Tool> tools, ToolType type) {
    return tools.firstWhereOrNull((tool) => tool.type.type == type);
  }

  /// Place upper track on plate with distance s.
  /// The upper track is aligned with the plate.
  /// This method is called when the [SimulationToolsChanged] event is emitted.
  /// The upper track is placed on the plate at the same position as the plate.
  Tool _placeUpperTrackOnPlate(Tool upperTrack, Tool plate) {
    double s = plate.s;

    Line selectedLine =
        plate.lines.firstWhereOrNull((line) => line.isSelected) ??
            plate.lines.first;

    List<Offset> trackOffsets =
        upperTrack.lines.map((line) => line.start).toList() +
            plate.lines.map((line) => line.end).toList();

    Offset plateOffset = _calculationsService
        .getLowestX([selectedLine.start, selectedLine.end]).first;

    List<Offset> lowestXTrackOffset =
        _calculationsService.getLowestX(trackOffsets);

    Offset trackOffset =
        _calculationsService.getLowestY(lowestXTrackOffset).first;

    Offset newOffset = trackOffset - plateOffset + new Offset(s - 7, s - 3);

    Tool movedTool = _moveTool(upperTrack, newOffset, false);
    return movedTool;
  }

  /// Rotate a [tool] clockwise around [center] by [degrees].
  Tool _rotateTool2(Tool tool, Offset center, double degrees) {
    return tool.copyWith(
        lines: _calculationsService.rotateLines(tool.lines, center, degrees));
  }

  void _rotateTool(
      SimulationToolRotate event, Emitter<SimulationPageState> emit) {
    Tool rotatedTool = _rotTool(event.tool, event.degrees);

    emit(state.copyWith(selectedPlates: []));
    emit(state.copyWith(selectedPlates: [rotatedTool], collisionOffsets: []));
  }

  // TODO
  Tool _rotTool(Tool tool, double degrees) {
    Line selectedLine = tool.lines.firstWhere((line) => line.isSelected);
    Offset center =
        _calculationsService.getMiddle(selectedLine.start, selectedLine.end);
    List<Line> rotatedLines =
        _calculationsService.rotateLines(tool.lines, center, degrees);

    return tool.copyWith(lines: rotatedLines);
  }

  /// Rotate the given [tool] around the center of the selected line of that
  /// tool until a the given [angle] is reached.
  /// The [stepSize] sets how much the tool is rotated each time.
  /// This method is called when the [SimulationToolsChanged] event is emitted.
  Tool _rotateUntilSelectedLineHasAngle(
      Tool tool, List<double> angles, double stepSize) {
    Line selectedLine = tool.lines.firstWhere((line) => line.isSelected);
    Offset center =
        _calculationsService.getMiddle(selectedLine.start, selectedLine.end);

    int steps = (360 / stepSize).floor();

    for (int i = 0; i < steps; i++) {
      tool = _rotateTool2(tool, center, stepSize);
      Line selectedLine = tool.lines.firstWhere((line) => line.isSelected);
      double currentAngle =
          _calculationsService.getAngle(selectedLine.start, selectedLine.end);
      if (angles.contains(currentAngle.round())) {
        return tool;
      }
    }
    return tool;
  }

  /// Mirror a [tool].
  void _onMirrorTool(
      SimulationToolMirrored event, Emitter<SimulationPageState> emit) {
    Tool lowerTrack = state.selectedTracks
        .firstWhere((tool) => tool.type.type == ToolType.lowerTrack);

    Tool mirroredTool = _mirrorTool(event.tool);
    Tool placedPlate = _placePlateOnTrack(emit, mirroredTool, lowerTrack);

    List<Tool> selectedPlates = state.selectedPlates;
    selectedPlates
      ..removeLast()
      ..add(placedPlate);

    emit(state.copyWith(selectedPlates: []));
    emit(state.copyWith(selectedPlates: [mirroredTool]));
  }

  Tool _mirrorTool(Tool tool) {
    Line selectedLine = tool.lines.firstWhere((line) => line.isSelected);

    Offset middle =
        _calculationsService.getMiddle(selectedLine.start, selectedLine.end);

    List<Line> mirroredLines =
        _calculationsService.mirrorLines(tool.lines, middle.dx);

    return tool.copyWith(lines: mirroredLines);
  }

  void _onCollisionDetect(
      SimulationCollisionDetected event, Emitter<SimulationPageState> emit) {
    bool result = false;

    collisionOffsets.clear();
    for (int i = 0; i < event.plateOffsets.length; i++) {
      if (event.collisionOffsets.contains(event.plateOffsets[i])) {
        collisionOffsets.add(event.plateOffsets[i]);
      }
    }

    collisionOffsets.isNotEmpty ? result = true : result = false;

    Line selectedLine =
        state.selectedPlates.first.lines.firstWhere((line) => line.isSelected);
    double angle =
        _calculationsService.getAngle(selectedLine.start, selectedLine.end);

    List<SimulationToolResult> simulationResults = state.simulationResults;
    SimulationToolResult? toolResult = simulationResults.firstWhereOrNull(
        (result) => result.tool.name == state.selectedPlates.first.name);

    if (toolResult == null) {
      toolResult = new SimulationToolResult(
          tool: state.selectedPlates.first,
          angleOfTool: angle,
          collisionResults: []);
    }

    if (state.currentTick < 10) {
      toolResult.collisionResults
          .add(new CollisionResult(angle: angle, isCollision: result));

      simulationResults
        ..removeWhere(
            (result) => result.tool.name == state.selectedPlates.first.name)
        ..add(toolResult);

      emit(state.copyWith(simulationResults: []));
      emit(state.copyWith(
          inCollision: result,
          collisionOffsets: collisionOffsets,
          simulationResults: simulationResults));
    } else {
      CollisionResult collisionResult =
          new CollisionResult(angle: angle, isCollision: result);

      SimulationToolResult toolResult = new SimulationToolResult(
          tool: state.selectedPlates.first,
          angleOfTool: angle,
          collisionResults: [collisionResult]);

      List<SimulationToolResult> simulationResults = _addCollisionResult(
          state.selectedPlates.first, collisionResult, angle, emit);

      emit(state.copyWith(
          inCollision: result,
          collisionOffsets: collisionOffsets,
          simulationResults: simulationResults));
    }
  }

  List<SimulationToolResult> _addCollisionResult(
      Tool tool,
      CollisionResult collisionResult,
      double angle,
      Emitter<SimulationPageState> emit) {
    List<SimulationToolResult> simulationResults = state.simulationResults;

    if (simulationResults.length > 1) {
      if (simulationResults.last.angleOfTool == angle) {
        return simulationResults;
      }
    }

    SimulationToolResult? resultTool =
        simulationResults.firstWhereOrNull((result) => result.tool == tool);

    if (resultTool == null) {
      SimulationToolResult toolResult = new SimulationToolResult(
          tool: tool, angleOfTool: angle, collisionResults: [collisionResult]);

      simulationResults.add(toolResult);
    } else {
      int index = simulationResults.indexOf(resultTool);
      resultTool.collisionResults.add(collisionResult);

      simulationResults
        ..removeAt(index)
        ..insert(index, resultTool);
    }

    return simulationResults;
  }

  /// Places the lower track on the on the lower beam.
  /// The lower track is aligned with the lower beam.
  /// The lower track is placed on the lower beam at the same position as the
  /// lower beam.
  ///
  /// When the lower beam does not exist nothing happens.
  ///
  /// This method is called when the [SimulationToolsChanged] event is emitted.
  void _placeLowerTrackOnLowerBeam(SimulationToolsChanged event,
      List<Tool> selectedTracks, Emitter<SimulationPageState> emit) {
    Tool? lowerBeam = _getToolByType(event.tools, ToolType.lowerBeam);
    Tool? lowerTrack = _getToolByType(event.tools, ToolType.lowerTrack);

    if (lowerBeam == null || lowerTrack == null) {
      return;
    }

    Tool newTrack = _placeTrackOnBeam(lowerTrack, lowerBeam);

    int index = selectedTracks.indexOf(lowerTrack);
    selectedTracks
      ..removeAt(index)
      ..insert(index, newTrack);

    // lowerTrack = lowerTrack.copyWith(lines: newTrack.lines);

    emit(state.copyWith(selectedTracks: selectedTracks));
  }

  /// Places the plate profile on the lower track.
  /// The plate profile is aligned with the lower track.
  ///
  /// The plate profile is placed on the lower track at the same position as the
  /// lower track.
  ///
  /// When the lower track or the plate does not exist nothing happens.
  /// This method is called when the [SimulationToolsChanged] event is emitted.
  void _placePlateOnLowerTrack(SimulationToolsChanged event,
      Emitter<SimulationPageState> emit, List<Tool> selectedPlates) {
    // Tool? lowerTrack = _getToolByType(event.tools, ToolType.lowerTrack);
    Tool? plate = _getToolByType(event.tools, ToolType.plateProfile);

    Tool? lowerTrack = state.selectedTracks
        .firstWhereOrNull((tool) => tool.type.type == ToolType.lowerTrack);

    if (lowerTrack == null || plate == null) {
      return;
    }

    List<Line> plateLines = plate.lines;
    plateLines.first.isSelected = true;

    plate = plate.copyWith(lines: plateLines);

    Tool placedPlate = _placePlateOnTrack(emit, plate, lowerTrack);

    emit(state.copyWith(
      selectedPlates: [placedPlate],
      simulationResults: [],
      bendingHistory: [],
    ));
  }

  /// Places the upper track on the plate profile.
  /// The upper track is aligned with the plate profile.
  /// The upper track is placed on the plate profile at the same position as the
  /// plate profile.
  ///
  /// This method is called when the [SimulationToolsChanged] event is emitted.
  void _placeUpperTrackOnPlate2(SimulationToolsChanged event,
      Emitter<SimulationPageState> emit, List<Tool> selectedTracks) {
    Tool? upperTrack = _getToolByType(event.tools, ToolType.upperTrack);
    Tool? plate = state.selectedPlates.first;
    // Tool? plate = _getToolByType(event.tools, ToolType.plateProfile);

    if (upperTrack == null || plate == null) {
      return;
    }

    Tool currentUpperTrack = selectedTracks
        .firstWhere((tool) => tool.type.type == ToolType.upperTrack);

    Tool placedTrack = _placeUpperTrackOnPlate(currentUpperTrack, plate);

    selectedTracks
      ..remove(currentUpperTrack)
      ..add(placedTrack);

    // upperTrack = upperTrack.copyWith(lines: placedTrack.lines);

    emit(state.copyWith(selectedTracks: selectedTracks));
  }

  /// Places the upper beam on upper track.
  /// The upper beam is aligned with the upper track.
  /// The upper beam is placed on the upper track at the same position as the
  /// upper track.
  ///
  /// When the upper track does not exist nothing happens.
  /// This method is called when the [SimulationToolsChanged] event is emitted.
  void _placeUpperBeamOnUpperTack2(
      SimulationToolsChanged event,
      Emitter<SimulationPageState> emit,
      List<Tool> selectedTracks,
      selectedBeams) {
    // Tool? upperBeam = _getToolByType(event.tools, ToolType.upperBeam);
    // Tool? upperTrack = _getToolByType(event.tools, ToolType.upperTrack);

    Tool? upperBeam = _getToolByType(selectedBeams, ToolType.upperBeam);
    Tool? upperTrack = _getToolByType(selectedTracks, ToolType.upperTrack);

    if (upperBeam == null || upperTrack == null) {
      return;
    }

    Tool placedBeam = _placeTrackOnBeam(upperBeam, upperTrack);

    Tool currentUpperBeam = selectedBeams
        .firstWhere((tool) => tool.type.type == ToolType.upperBeam);

    selectedBeams
      ..remove(currentUpperBeam)
      ..add(placedBeam);

    emit(state.copyWith(selectedBeams: selectedBeams));
  }

  /// Starts the simulation
  void _onSimulationStart(
      SimulationStarted event, Emitter<SimulationPageState> emit) {
    add(SimulationTicked());

    emit(state.copyWith(
        isSimulationRunning: true, currentTick: 0, simulationResults: []));
  }

  void _testAllSidesOfPlateForCollision(
      Tool plate, int currentTick, Emitter<SimulationPageState> emit) {
    if (currentTick > 4) {
      add(SimulationTicked());
    }
  }

  /// Stops the simulation
  void _onSimulationStopped(
      SimulationStopped event, Emitter<SimulationPageState> emit) {
    emit(state.copyWith(isSimulationRunning: false, currentTick: 9999));
  }

  /// Rudimentary algorithm for the simulation.
  /// TODO Reduce code duplication and interoperability.
  ///
  /// 1. Tests all sites of a plate (tick 1-4)
  /// 2. Mirrors the tool (tick 5)
  /// 3. Tests all other sites (tick 6-9)
  void _onTicked(SimulationTicked event, Emitter<SimulationPageState> emit) {
    int tick = state.currentTick;

    if (state.isSimulationRunning == false) {
      return;
    }

    if (tick < 4) {
      Tool plate = state.selectedPlates.first;
      Tool rotatedPlate = _rotTool(plate, 90);

      tick++;

      emit(state.copyWith(selectedPlates: []));
      emit(state.copyWith(
          selectedPlates: [rotatedPlate],
          collisionOffsets: [],
          currentTick: tick));
    } else if (tick == 3) {
      Tool mirroredTool = _mirrorTool(state.selectedPlates.first);
      tick++;
      emit(state.copyWith(selectedPlates: []));
      emit(state.copyWith(selectedPlates: [mirroredTool], currentTick: tick));
    } else if (tick < 8 && state.isSimulationRunning) {
      Tool plate = state.selectedPlates.first;
      Tool rotatedPlate = _rotTool(plate, 90);

      tick++;

      emit(state.copyWith(selectedPlates: []));
      emit(state.copyWith(
          selectedPlates: [rotatedPlate],
          collisionOffsets: [],
          currentTick: tick));
    } else {
      add(SimulationStopped());
    }
  }

  void _onUnbendPlate2(
      SimulationPlateUnbended event, Emitter<SimulationPageState> emit) {
    Tool plate = event.plate.copyWith();
    List<BendResult> bendResults = state.bendingHistory;
    List<DebuggingOffset> debuggingOffsets = [];

    if (bendResults.isEmpty) {
      _addBendingResult(event.plate, 0, emit);
    }

    int indexOfSelectedLine = _getIndexOfSelectedLine(event.plate);
    Line selectedLine = plate.lines[indexOfSelectedLine].copyWith();

    /// Rotate Line To bend + rest
    List<Line> linesToRotate = plate.lines
        .getRange(indexOfSelectedLine + 1, plate.lines.length)
        .toList();

    List<Line> rotatedLines = _calculationsService.rotateLines(
        linesToRotate, linesToRotate.first.start, 270);

    ///  Merge selected line and bended line
    List<Line> currentLines = plate.copyWith().lines;
    selectedLine = selectedLine.copyWith(end: rotatedLines.first.end);
    rotatedLines.removeAt(0);

    currentLines
      ..removeRange(indexOfSelectedLine, currentLines.length)
      ..insert(indexOfSelectedLine, selectedLine)
      ..addAll(rotatedLines);

    double angle =
        _calculationsService.getAngle(selectedLine.start, selectedLine.end);
    Tool newPlate = plate.copyWith(lines: currentLines);
    List<BendResult> newBendResults = bendResults
      ..add(new BendResult(tool: newPlate, angle: angle));

    emit(state.copyWith(
        debugOffsets: debuggingOffsets,
        selectedPlates: [newPlate],
        bendingHistory: newBendResults));
  }

  /// Return the index of the currently selected [Line] of the given [plate].
  ///
  int _getIndexOfSelectedLine(Tool plate) {
    /// Get Line To bend
    Line selectedLine =
        plate.lines.firstWhere((line) => line.isSelected == true);

    return plate.lines.indexOf(selectedLine);
  }

  void _onBendPlate(
      SimulationPlateBended event, Emitter<SimulationPageState> emit) {
    List<BendResult> bendResults = state.bendingHistory;
    bendResults.removeLast();

    Tool lastTool = _rotTool(bendResults.last.tool, bendResults.last.angle);

    emit(state.copyWith(selectedPlates: [], simulationResults: []));
    emit(state
        .copyWith(bendingHistory: bendResults, selectedPlates: [lastTool]));
  }

  /// Add [BendingResult] to state.
  void _addBendingResult(
      Tool tool, double angle, Emitter<SimulationPageState> emit) {
    List<BendResult> bendResults = state.bendingHistory;
    bendResults.add(new BendResult(tool: tool.copyWith(), angle: angle));

    emit(state.copyWith(bendingHistory: bendResults));
  }
}
