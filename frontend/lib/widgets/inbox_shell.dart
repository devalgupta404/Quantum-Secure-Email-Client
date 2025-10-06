import 'package:flutter/material.dart';
import '../app.dart';

class InboxTopBar extends StatelessWidget {
	const InboxTopBar({super.key, required this.trailing});

	final List<Widget> trailing;

	@override
	Widget build(BuildContext context) {
		final colorScheme = Theme.of(context).colorScheme;
		final blue = Colors.blue;
		return Container(
			padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
			decoration: BoxDecoration(
				color: colorScheme.surface,
				border: Border(
					bottom: BorderSide(color: Colors.grey.shade300),
				),
			),
			child: Row(
				children: [
					Row(
						children: [
							Container(
								width: 32,
								height: 32,
								decoration: BoxDecoration(
									color: blue.shade600,
									borderRadius: BorderRadius.circular(8),
								),
								alignment: Alignment.center,
								child: const Text(
									'Q',
									style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
								),
							),
							const SizedBox(width: 10),
							Text(
								'QuMail',
								style: TextStyle(
									fontSize: 18,
									fontWeight: FontWeight.w700,
									color: blue.shade700,
								),
							),
						],
					),
					const SizedBox(width: 16),
					Expanded(
						child: Container(
							height: 40,
							padding: const EdgeInsets.symmetric(horizontal: 12),
							decoration: BoxDecoration(
								color: Colors.grey.shade100,
								borderRadius: BorderRadius.circular(8),
								border: Border.all(color: Colors.grey.shade300),
							),
							child: const Row(
								children: [
									Icon(Icons.search, color: Colors.grey),
									SizedBox(width: 8),
									Expanded(
										child: TextField(
											decoration: InputDecoration(
												hintText: 'Search mail',
												border: InputBorder.none,
												isCollapsed: true,
											),
										),
									),
								],
							),
						),
					),
					const SizedBox(width: 16),
					...trailing,
				],
			),
		);
	}
}

class InboxSidebar extends StatelessWidget {
	const InboxSidebar({super.key, required this.active});

	final String active; // 'inbox' | 'flagged' | 'drafts' | 'sent' | 'trash' | 'compose'

	@override
	Widget build(BuildContext context) {
		final blue = Colors.blue;
		Widget item({
			required IconData icon,
			required String label,
			required String keyName,
			required VoidCallback onTap,
		}) {
			final bool isActive = keyName == active;
			return InkWell(
				onTap: onTap,
				child: Container(
					padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
					decoration: BoxDecoration(
						color: isActive ? blue.shade50 : null,
						border: Border(
							bottom: BorderSide(color: Colors.grey.shade200),
							left: BorderSide(color: isActive ? blue.shade600 : Colors.transparent, width: 3),
						),
					),
					child: Row(
						children: [
							Icon(icon, color: isActive ? blue.shade700 : Colors.grey.shade700),
							const SizedBox(width: 12),
							Expanded(
								child: Text(
									label,
									style: TextStyle(
										fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
										color: isActive ? blue.shade800 : Colors.grey.shade800,
									),
								),
							),
						],
					),
				),
			);
		}

		return Container(
			width: 240,
			decoration: BoxDecoration(
				color: Colors.grey.shade50,
				border: Border(
					right: BorderSide(color: Colors.grey.shade300),
				),
			),
			child: Column(
				crossAxisAlignment: CrossAxisAlignment.stretch,
				children: [
					Padding(
						padding: const EdgeInsets.all(16),
						child: ElevatedButton.icon(
							style: ElevatedButton.styleFrom(
								backgroundColor: blue.shade600,
								foregroundColor: Colors.white,
								padding: const EdgeInsets.symmetric(vertical: 14),
								shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
							),
							onPressed: () => Navigator.pushNamed(context, Routes.compose),
							icon: const Icon(Icons.edit_outlined),
							label: const Text('Compose'),
						),
					),
					item(icon: Icons.inbox_outlined, label: 'Inbox', keyName: 'inbox', onTap: () => Navigator.pushNamed(context, Routes.inbox)),
					item(icon: Icons.flag_outlined, label: 'Flagged', keyName: 'flagged', onTap: () {}),
					item(icon: Icons.send_outlined, label: 'Sent', keyName: 'sent', onTap: () => Navigator.pushNamed(context, Routes.sent)),
					item(icon: Icons.drafts_outlined, label: 'Draft', keyName: 'drafts', onTap: () {}),
					item(icon: Icons.delete_outline, label: 'Trash', keyName: 'trash', onTap: () {}),
					const Spacer(),
				],
			),
		);
	}
}

class MobileScaffoldShell extends StatelessWidget {
	const MobileScaffoldShell({super.key, required this.title, required this.body});

	final String title;
	final Widget body;

	@override
	Widget build(BuildContext context) {
		final blue = Colors.blue;
		return Scaffold(
			appBar: AppBar(
				backgroundColor: blue.shade600,
				foregroundColor: Colors.white,
				centerTitle: false,
				title: Text(title),
				actions: [
					IconButton(
						onPressed: () => Navigator.pushNamed(context, Routes.settings),
						icon: const Icon(Icons.settings_outlined),
					),
				],
			),
				drawer: Drawer(
				child: SafeArea(
					child: Column(
						crossAxisAlignment: CrossAxisAlignment.stretch,
						children: [
							ListTile(leading: const Icon(Icons.inbox_outlined), title: const Text('Inbox'), onTap: () => Navigator.pushNamed(context, Routes.inbox)),
							ListTile(leading: const Icon(Icons.flag_outlined), title: const Text('Flagged'), onTap: () {}),
							ListTile(leading: const Icon(Icons.drafts_outlined), title: const Text('Drafts'), onTap: () {}),
							ListTile(leading: const Icon(Icons.send_outlined), title: const Text('Sent'), onTap: () => Navigator.pushNamed(context, Routes.sent)),
							ListTile(leading: const Icon(Icons.delete_outline), title: const Text('Trash'), onTap: () {}),
						],
					),
				),
			),
			body: body,
		);
	}
}


