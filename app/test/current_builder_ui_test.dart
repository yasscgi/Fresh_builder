import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_builder/src/workspace/current_builder_ui.dart';

void main() {
  testWidgets('mobile category navigator switches active category', (tester) async {
    var selected = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            return Scaffold(
              body: CurrentBuilderMobileCategoryNav(
                categories: const [
                  (Icons.layers_rounded, 'Base'),
                  (Icons.checkroom_rounded, 'Hat'),
                  (Icons.accessibility_new_rounded, 'Pose'),
                ],
                selected: selected,
                onSelect: (index) => setState(() => selected = index),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Hat'));
    await tester.pumpAndSettle();
    expect(selected, 1);
  });

  testWidgets('compact rig rail exposes IK FK and hand actions', (tester) async {
    var ik = false;
    var fk = false;
    var handOpen = true;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return CurrentBuilderRigRail(
                ikActive: ik,
                fkActive: fk,
                handOpen: handOpen,
                onIk: () => setState(() => ik = !ik),
                onFk: () => setState(() => fk = !fk),
                onOpenHand: () => setState(() => handOpen = true),
                onCloseHand: () => setState(() => handOpen = false),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('IK'));
    await tester.pump();
    expect(ik, isTrue);

    await tester.tap(find.text('Close'));
    await tester.pump();
    expect(handOpen, isFalse);
  });

  testWidgets('view controls emit semantic presets', (tester) async {
    CurrentBuilderViewPreset? preset;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CurrentBuilderViewControls(
            onView: (value) => preset = value,
          ),
        ),
      ),
    );

    await tester.tap(find.text('FRONT'));
    await tester.pump();
    expect(preset, CurrentBuilderViewPreset.front);
  });
}
