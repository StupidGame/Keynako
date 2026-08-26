part of 'customization_page.dart';

class TabBarEditorPage extends StatelessWidget {
  const TabBarEditorPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AppControllerScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('タブバーを編集')),
      body: ReorderableListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: controller.data.tabBar.length,
        onReorderItem: controller.reorderTabBar,
        itemBuilder: (context, index) {
          final item = controller.data.tabBar[index];
          return Card(
            key: ValueKey(item),
            child: ListTile(
              leading: const Icon(Icons.drag_handle),
              title: Text(_tabLabel(controller.data, item)),
              trailing: const Icon(Icons.reorder),
            ),
          );
        },
      ),
    );
  }

  String _tabLabel(AppData data, String value) {
    if (value.startsWith('custom:')) {
      final id = value.substring('custom:'.length);
      for (final tab in data.customTabs) {
        if (tab.id == id) return tab.name;
      }
      for (final custard in data.custards) {
        if (custard.identifier == id) return custard.displayName;
      }
      return '不明なカスタムタブ';
    }
    return const {
          'dismiss': 'キーボードを閉じる',
          'resize': '片手モード',
          'emoji': '絵文字',
          'japanese': 'あいう',
          'english': 'ABC',
          'clipboard': 'コピー履歴',
        }[value] ??
        value;
  }
}
