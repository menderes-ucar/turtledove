import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../localization/app_strings.dart';

class CallHistoryScreen extends StatelessWidget {
  const CallHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return Scaffold(body: Center(child: Text(AppStrings.of(context).sessionNotFound)));
    final uid = user.id;
    return Scaffold(
      appBar: AppBar(title: Text(AppStrings.of(context).callHistory)),
      body: FutureBuilder<List<Map<String,dynamic>>>(
        future: Supabase.instance.client.from('call_sessions').select('id,caller_id,receiver_id,status,created_at,ended_at').or('caller_id.eq.$uid,receiver_id.eq.$uid').order('created_at', ascending: false).limit(100),
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const Center(child:CircularProgressIndicator());
          if (snap.hasError) return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('${AppStrings.of(context).callHistoryLoadFailed}\n${snap.error}', textAlign: TextAlign.center)));
          final rows = snap.data ?? [];
          if (rows.isEmpty) return Center(child: Text(AppStrings.of(context).noCallHistory));
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: rows.length,
            separatorBuilder: (_,__)=>const SizedBox(height:10),
            itemBuilder: (_,i) {
              final r=rows[i];
              final outgoing=r['caller_id']==uid;
              final status=(r['status']??'').toString();
              final created=DateTime.tryParse((r['created_at']??'').toString());
              final ended=DateTime.tryParse((r['ended_at']??'').toString());
              final duration=created!=null && ended!=null ? ended.difference(created) : null;
              final icon=status=='rejected'||status=='ended' ? (outgoing?Icons.call_made:Icons.call_received) : Icons.call;
              return Card(
                child: ListTile(
                  leading: CircleAvatar(child: Icon(icon)),
                  title: Text(outgoing ? AppStrings.of(context).outgoingCall : AppStrings.of(context).incomingCallHistory),
                  subtitle: Text('${created==null?'':DateFormat('dd.MM.yyyy HH:mm').format(created)}${duration!=null?' • ${duration.inMinutes} ${AppStrings.of(context).minutesShort}':''}'),
                  trailing: Text(status == 'rejected' ? AppStrings.of(context).rejectedCall : status == 'ended' ? AppStrings.of(context).endedCall : status),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
