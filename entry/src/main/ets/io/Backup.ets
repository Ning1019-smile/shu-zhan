import { fileIo as fs, picker } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';

function dateTag(): string {
  const d = new Date();
  const p = (n: number): string => (n < 10 ? `0${n}` : `${n}`);
  return `${d.getFullYear()}${p(d.getMonth() + 1)}${p(d.getDate())}_${p(d.getHours())}${p(d.getMinutes())}`;
}

// 弹出系统"另存为"，把备份 JSON 写入用户选择的位置。返回是否成功写入。
export async function exportBackup(json: string): Promise<boolean> {
  const opts = new picker.DocumentSaveOptions();
  opts.newFileNames = [`导读工作台备份_${dateTag()}.json`];
  const view = new picker.DocumentViewPicker();
  const uris: Array<string> = await view.save(opts);
  if (!uris || uris.length === 0) {
    return false;
  }
  const file = fs.openSync(uris[0], fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
  fs.writeSync(file.fd, json);
  fs.closeSync(file.fd);
  return true;
}

// 弹出系统"打开文件"，读取用户选择的备份 JSON。取消返回 null。
export async function importBackup(): Promise<string | null> {
  const opts = new picker.DocumentSelectOptions();
  opts.maxSelectNumber = 1;
  const view = new picker.DocumentViewPicker();
  const uris: Array<string> = await view.select(opts);
  if (!uris || uris.length === 0) {
    return null;
  }
  const file = fs.openSync(uris[0], fs.OpenMode.READ_ONLY);
  const stat = fs.statSync(file.fd);
  const buf = new ArrayBuffer(stat.size);
  fs.readSync(file.fd, buf);
  fs.closeSync(file.fd);
  return util.TextDecoder.create('utf-8').decodeToString(new Uint8Array(buf));
}
