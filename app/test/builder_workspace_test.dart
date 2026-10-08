import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_builder/src/workspace/builder_workspace.dart';

void main() {
  test('view preset state is semantic and independent from tools', () {
    final controller = BuilderWorkspaceController();

    controller.setViewPreset('top');
    expect(controller.viewPreset, 'top');
    expect(controller.status, 'TOP view');
    expect(controller.tool, BuilderTool.select);

    controller.dispose();
  });

  test('transform tool selection is deterministic', () {
    final controller = BuilderWorkspaceController();
    expect(controller.tool, BuilderTool.select);

    controller.selectTool(BuilderTool.rotate);
    expect(controller.tool, BuilderTool.rotate);

    controller.dispose();
  });

  test('pose gesture locks navigation until commit', () {
    final controller = BuilderWorkspaceController();

    controller.beginPoseGesture();
    expect(controller.navigationLocked, isTrue);

    controller.commitPoseGesture();
    expect(controller.navigationLocked, isFalse);
    expect(controller.status, 'Pose committed');

    controller.dispose();
  });

}
