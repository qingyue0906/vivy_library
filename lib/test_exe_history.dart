import 'models/exe_record.dart';
import 'services/exe_history_service.dart';

void main() async {
  final service = ExeHistoryService();

  print('--- 初始状态 ---');
  print(await service.loadAll());

  print('--- 添加一条记录 ---');
  await service.addRecord(
    const ExeRecord(path: r'C:\Windows\System32\notepad.exe', displayName: '记事本'),
  );
  print(await service.loadAll());

  print('--- 再添加一条 ---');
  await service.addRecord(
    const ExeRecord(path: r'C:\Program Files\VSCode\Code.exe', displayName: 'VS Code'),
  );
  print(await service.loadAll());

  print('--- 删除第一条 ---');
  await service.removeRecord(r'C:\Windows\System32\notepad.exe');
  print(await service.loadAll());
}