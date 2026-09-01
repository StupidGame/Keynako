import 'package:flutter/material.dart';

import '../../core/app_controller.dart';
import '../../core/platform_service.dart';
import '../../widgets/keyboard_preview.dart';

class TipsPage extends StatefulWidget {
  const TipsPage({super.key});

  @override
  State<TipsPage> createState() => _TipsPageState();
}

class _TipsPageState extends State<TipsPage> {
  var _status = KeyboardStatus.unavailable;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _refresh();
  }

  Future<void> _refresh() async {
    final status = await AppControllerScope.of(context).platform
        .keyboardStatus();
    if (mounted &&
        (status.enabled != _status.enabled ||
            status.fullAccess != _status.fullAccess ||
            status.platform != _status.platform)) {
      setState(() => _status = status);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: 'Key',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              TextSpan(
                text: 'nako',
                style: TextStyle(fontWeight: FontWeight.w300),
              ),
            ],
          ),
        ),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _ActivationCard(status: _status, refresh: _refresh),
          const SizedBox(height: 18),
          _sectionTitle(context, 'キーボードを使えるようにする'),
          _tip(
            context,
            icon: Icons.keyboard_alt_outlined,
            title: '入力方法を選ぶ',
            body: 'フリック入力とローマ字入力は設定から言語ごとに選択できます。',
          ),
          _tip(
            context,
            icon: Icons.science_outlined,
            title: 'キーボードを試す',
            body: '実際の入力欄で、変換・フリック・カスタムタブを確認します。',
            destination: const KeyboardSandboxPage(),
          ),
          const SizedBox(height: 18),
          _sectionTitle(context, '便利な使い方'),
          for (final article in _articles)
            _tip(
              context,
              icon: article.icon,
              title: article.title,
              body: article.summary,
              destination: GuideArticlePage(article: article),
            ),
          const SizedBox(height: 18),
          _sectionTitle(context, '困ったときは'),
          _tip(
            context,
            icon: Icons.web_asset_off_outlined,
            title: '特定のアプリで入力がおかしい',
            body: '設定の「入力中のテキストを保護」を自動または有効に変更してください。',
          ),
          _tip(
            context,
            icon: Icons.sentiment_neutral_outlined,
            title: '絵文字や顔文字を候補に表示する',
            body: '設定の「絵文字と顔文字」から辞書を有効にできます。',
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
      child: Text(title, style: Theme.of(context).textTheme.titleMedium),
    );
  }

  Widget _tip(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String body,
    Widget? destination,
  }) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
        title: Text(title),
        subtitle: Text(body, maxLines: 2, overflow: TextOverflow.ellipsis),
        trailing: destination == null ? null : const Icon(Icons.chevron_right),
        onTap: destination == null
            ? null
            : () => Navigator.of(context)
                  .push(MaterialPageRoute<void>(builder: (_) => destination)),
      ),
    );
  }
}

class _ActivationCard extends StatelessWidget {
  const _ActivationCard({required this.status, required this.refresh});

  final KeyboardStatus status;
  final Future<void> Function() refresh;

  @override
  Widget build(BuildContext context) {
    final controller = AppControllerScope.of(context);
    final enabled = status.enabled;
    return Card(
      color: enabled
          ? Theme.of(context).colorScheme.primaryContainer
          : Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Icon(enabled ? Icons.check_circle : Icons.info_outline, size: 36),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    enabled ? 'キーボードは有効です' : 'キーボードを有効にしてください',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    enabled ? '設定はキーボードへ自動的に反映されます。' : '端末の設定画面でKeynakoを追加します。',
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: '設定を開く',
              onPressed: () async {
                await controller.platform.openKeyboardSettings();
                await refresh();
              },
              icon: const Icon(Icons.open_in_new),
            ),
          ],
        ),
      ),
    );
  }
}

class GuideArticle {
  const GuideArticle({
    required this.title,
    required this.summary,
    required this.icon,
    required this.sections,
  });

  final String title;
  final String summary;
  final IconData icon;
  final List<(String, String)> sections;
}

const _articles = [
  GuideArticle(
    title: '片手モードを使う',
    summary: '横幅と位置を調整し、大きな画面でも片手で入力できます。',
    icon: Icons.aspect_ratio,
    sections: [
      ('開始', 'タブバーのサイズ変更ボタンを押し、左右どちらへ寄せるか選びます。'),
      ('調整', '端のハンドルをドラッグすると幅を調整できます。もう一度ボタンを押すと通常表示へ戻ります。'),
    ],
  ),
  GuideArticle(
    title: 'カーソルを自由に移動する',
    summary: '空白キーまたはカーソルキーを長押しして指を動かします。',
    icon: Icons.swap_horiz,
    sections: [
      ('操作', '空白キーを長押ししたまま左右へ動かすと、入力カーソルが追従します。'),
      ('設定', '設定の「新しいカーソルバーを使う」で表示方式を切り替えられます。'),
    ],
  ),
  GuideArticle(
    title: '単語や範囲をすばやく消す',
    summary: '削除キーを素早く2回押すと、直前の1単語を削除します。',
    icon: Icons.backspace_outlined,
    sections: [
      ('単語削除', '削除キーを素早く2回押すか左へフリックすると、カーソル直前の1単語を削除します。'),
      ('カスタムタブ', 'カスタムタブや読み込んだCustardでは、「単語削除」アクションが同じ1単語境界を使います。'),
      ('スムーズ削除', '削除キーを押したまま左へ動かすと削除範囲が広がります。指を戻すと範囲も戻ります。'),
    ],
  ),
  GuideArticle(
    title: '漢字を拡大表示する',
    summary: '変換候補を長押しして、細かな字形を確認できます。',
    icon: Icons.zoom_in,
    sections: [('候補の確認', '変換候補を長押しすると候補を大きく表示します。難しい漢字の確認に便利です。')],
  ),
  GuideArticle(
    title: '大文字に固定する',
    summary: 'QWERTYのシフトキーを素早く2回押してCaps Lockにします。',
    icon: Icons.keyboard_capslock,
    sections: [('Caps Lock', 'シフトキーを2回押すと大文字入力を固定し、もう一度押すと解除します。')],
  ),
  GuideArticle(
    title: 'タイムスタンプを使う',
    summary: 'ユーザー辞書へ日時テンプレートを登録できます。',
    icon: Icons.schedule,
    sections: [('テンプレート', 'ユーザー辞書で「時刻・ランダム変換」を選び、yyyy/MM/ddやHH:mmの書式を登録します。')],
  ),
  GuideArticle(
    title: 'キーをカスタマイズする',
    summary: '入力、削除、カーソル移動、タブ移動などのアクションを割り当てます。',
    icon: Icons.handyman_outlined,
    sections: [('カスタムキー', '拡張タブでタップ、上下左右フリック、長押しの各アクションを編集できます。')],
  ),
  GuideArticle(
    title: 'フルアクセスが必要な機能',
    summary: 'クリップボード、連絡先、通信を使う機能だけ追加権限が必要です。',
    icon: Icons.lock_open,
    sections: [('プライバシー', '通常の文字入力とローカル変換には通信を使いません。追加権限が必要な機能は設定で明示されています。')],
  ),
];

class GuideArticlePage extends StatelessWidget {
  const GuideArticlePage({required this.article, super.key});

  final GuideArticle article;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(article.title)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Icon(
            article.icon,
            size: 72,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 18),
          Text(article.summary, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 20),
          for (final section in article.sections) ...[
            Text(section.$1, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(section.$2),
            const SizedBox(height: 18),
          ],
        ],
      ),
    );
  }
}
