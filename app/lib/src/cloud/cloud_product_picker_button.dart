import 'package:flutter/material.dart';

import 'builder_product_repository.dart';

class CloudProductPickerButton extends StatelessWidget {
  const CloudProductPickerButton({
    super.key,
    required this.cloudReady,
    required this.selectedProduct,
    required this.onSelected,
  });

  final bool cloudReady;
  final BuilderProductSummary? selectedProduct;
  final ValueChanged<BuilderProductSummary> onSelected;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: selectedProduct == null
          ? 'Open a Builder product'
          : selectedProduct!.name,
      onPressed: cloudReady ? () => _open(context) : null,
      icon: Icon(
        selectedProduct == null
            ? Icons.folder_open_rounded
            : Icons.view_in_ar_rounded,
        size: 20,
      ),
    );
  }

  Future<void> _open(BuildContext context) async {
    final repository = BuilderProductRepository();

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('FreshSTL Builder Library'),
          content: SizedBox(
            width: 460,
            height: 420,
            child: FutureBuilder<List<BuilderProductSummary>>(
              future: repository.listAccessibleBuilderProducts(),
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      snapshot.error.toString(),
                      textAlign: TextAlign.center,
                    ),
                  );
                }

                final products =
                    snapshot.data ?? const <BuilderProductSummary>[];
                if (products.isEmpty) {
                  return const Center(
                    child: Text(
                      'No Builder products are available for this account.',
                      textAlign: TextAlign.center,
                    ),
                  );
                }

                return ListView.separated(
                  itemCount: products.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final product = products[index];
                    final active = selectedProduct?.id == product.id;

                    return ListTile(
                      selected: active,
                      leading: Icon(
                        active
                            ? Icons.check_circle_rounded
                            : Icons.view_in_ar_outlined,
                      ),
                      title: Text(product.name),
                      subtitle: Text(
                        product.price == 0
                            ? 'Free Builder'
                            : 'FreshSTL access verified',
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () {
                        onSelected(product);
                        Navigator.pop(dialogContext);
                      },
                    );
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }
}
