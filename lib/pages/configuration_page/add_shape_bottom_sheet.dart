import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:open_bsp/bloc%20/configuration_page/configuration_page_bloc.dart';
import 'package:open_bsp/bloc%20/shapes_page/shapes_page_bloc.dart';
import 'package:open_bsp/model/simulation/tool.dart';
import 'package:open_bsp/persistence/database_service.dart';

import '../../model/line.dart';
import '../../model/simulation/tool_type.dart';

/// Bottom sheet which appears when the users adds a shape.
class AddShapeBottomSheet extends StatefulWidget {
  final Tool? selectedShape;

  const AddShapeBottomSheet({Key? key, required this.selectedShape})
      : super(key: key);

  @override
  State<AddShapeBottomSheet> createState() =>
      _AddShapeBottomSheetState(selectedShape: selectedShape);
}

class _AddShapeBottomSheetState extends State<AddShapeBottomSheet> {
  final _nameController = TextEditingController();
  bool lowerCheek = false;
  bool upperCheek = false;
  final Tool? selectedShape;

  String? dropdownValue = 'Unterwange';

  _AddShapeBottomSheetState({required this.selectedShape});

  DatabaseService _service = DatabaseService();

  /// Fills in the TextField and dropdown with initial values of the selected
  /// shape if present.
  @override
  void initState() {
    super.initState();
    if (selectedShape != null) {
      _nameController.text = selectedShape!.name;
      setState(() {
        dropdownValue = _getNameOfType(selectedShape!.type);
      });
    }
  }

  /// Disposes the TextField controller when page is not needed anymore.
  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  /// Builds the bottom sheet.
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 450,
      child: BlocBuilder<ConfigPageBloc, ConfigPageState>(
          builder: (context, state) {
        return Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(
            children: [
              buildTitleRow(),
              Divider(),
              buildNameRow(),
              buildButtonRow(state, context),
            ],
          ),
        );
      }),
    );
  }

  /// Builds the row containing two buttons.
  Row buildButtonRow(ConfigPageState state, BuildContext context) {
    return Row(
      children: [
        ElevatedButton(
          onPressed: () {
            List<Line> lines = context.read<ConfigPageBloc>().state.lines;
            _saveShape(_nameController.text, lines);
          },
          child: Text('Speichern'),
        ),
        Container(
          width: 10,
        ),
        ElevatedButton(
          onPressed: () {
            context
                .read<ShapesPageBloc>()
                .add(ShapesPageCreated(shapes: state.shapes));
            Navigator.of(context).pushNamed("/shapes");
          },
          child: Text('Übersicht Werkzeuge'),
        ),
      ],
    );
  }

  /// Builds the row where the suer can set the name and the type of the shape.
  Row buildNameRow() {
    return Row(
      children: [
        Container(
          width: 150,
          height: 50,
          child: TextField(
            controller: _nameController,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'Name',
            ),
          ),
        ),
        Container(width: 10),
        DropdownButton(
            value: dropdownValue,
            items: <String>['Unterwange', 'Oberwange', 'Biegewange']
                .map<DropdownMenuItem<String>>((String value) {
              return DropdownMenuItem<String>(
                value: value,
                child: Text(value),
              );
            }).toList(),
            onChanged: (String? newValue) {
              setState(() {
                dropdownValue = newValue!;
                print('dropdownvalue changed: ${newValue}');
              });
            }),
        Container(
          width: 10,
        ),
        Container(
          width: 20,
        ),
      ],
    );
  }

  /// Builds the row containing the title of the bottom sheet.
  Row buildTitleRow() {
    return Row(
      children: [
        Text(
          'Werkzeug hinzufügen',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  /// Saves the shape to the database and notified the [ShapesPageBloc].j
  void _saveShape(String name, List<Line> lines) {
    ToolType type = ToolType.upperBeam;

    switch (dropdownValue) {
      case 'Oberwange':
        type = ToolType.upperBeam;
        print('saved shape type: ${type}');
        break;
      case 'Unterwange':
        type = ToolType.lowerBeam;
        print('saved shape type: ${type}');
        break;
      case 'Biegewange':
        type = ToolType.bendingBeam;
        print('saved shape type: ${type}');
    }

    Tool shape =
        new Tool(name: _nameController.text, lines: lines, type: type);

    context.read<ShapesPageBloc>().add(ShapeAdded(shape: shape));

    if (selectedShape == null) {
      Navigator.of(context).pushNamed("/shapes");
    } else {
      Navigator.pop(context);
    }
  }

  /// Returns the name of the type of the shape.
  String _getNameOfType(ToolType type) {
    switch (type) {
      case ToolType.lowerBeam:
        return 'Unterwange';
      case ToolType.upperBeam:
        return 'Oberwange';
      case ToolType.bendingBeam:
        return 'Biegewange';
    }
  }
}
