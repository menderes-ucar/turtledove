import 'package:flutter/foundation.dart';
import '../../domain/entities/error_item.dart';
import '../../domain/repositories/error_notebook_repository.dart';
class ErrorNotebookProvider extends ChangeNotifier {
  final ErrorNotebookRepository repository;
  ErrorNotebookProvider(this.repository);
  List<ErrorItem> items=[];
  bool loading=false;
  bool showResolved=false;
  String? error;
  Future<void> load()async {
    loading=true;
    notifyListeners();
    try {
      items=await repository.list(resolved:showResolved?null:false);
      error=null;
    }
    catch(e) {
      error='Yanlış defteri yüklenemedi.';
    }
    finally {
      loading=false;
      notifyListeners();
    }
  }
  Future<void> resolve(String id)async {
    await repository.resolve(id);
    await load();
  }
  Future<void> reopen(String id)async {
    await repository.reopen(id);
    await load();
  }
  Future<void> setShowResolved(bool v)async {
    showResolved=v;
    await load();
  }
}
