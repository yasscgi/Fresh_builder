import 'package:flutter/foundation.dart';

import 'builder_repository.dart';

class BuilderRuntime extends ChangeNotifier {
  BuilderRuntime(this._repository);

  final BuilderRepository _repository;

  bool loading = false;
  String? error;
  BuilderProductBundle? bundle;

  Future<void> load({String? productId}) async {
    if (loading) return;

    loading = true;
    error = null;
    notifyListeners();

    try {
      final resolvedId = productId ?? await _resolveFirstProduct();
      bundle = await _repository.loadProduct(resolvedId);
    } catch (exception) {
      error = exception.toString();
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<String> _resolveFirstProduct() async {
    final ids = await _repository.listBuilderProductIds();
    if (ids.isEmpty) {
      throw StateError('No Builder-enabled product is available.');
    }
    return ids.first;
  }
}
