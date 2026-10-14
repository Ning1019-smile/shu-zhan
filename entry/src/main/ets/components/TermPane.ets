import { db } from '../database/Db';
import { Term } from '../model/Models';

// 术语表工作区：读中积累，页码锚点 + 个人理解
@Component
export struct TermPane {
  @Prop @Watch('onChapterChange') chapterId: number = -1;
  @State terms: Term[] = [];
  // 数据变化时通知父组件刷新全书速查/统计
  onChanged: () => void = (): void => {};
  // 新增表单
  @State draftName: string = '';
  @State draftDef: string = '';
  @State draftPage: string = '';
  // 编辑态
  @State editingId: number = -1;
  @State editName: string = '';
  @State editDef: string = '';
  @State editPage: string = '';
  @State editNote: string = '';

  aboutToAppear(): void {
    this.reload();
  }

  onChapterChange(): void {
    this.editingId = -1;
    this.reload();
  }

  private async reload(): Promise<void> {
    if (this.chapterId < 0) {
      this.terms = [];
      return;
    }
    this.terms = await db.getTerms(this.chapterId);
  }

  private async add(): Promise<void> {
    const name = this.draftName.trim();
    if (name === '' || this.chapterId < 0) {
      return;
    }
    const def = this.draftDef.trim();
    const page = this.draftPage.trim();
    this.draftName = '';
    this.draftDef = '';
    this.draftPage = '';
    await db.addTerm(this.chapterId, name, def, page, '');
    await this.reload();
    this.onChanged();
  }

  private startEdit(t: Term): void {
    this.editingId = t.id;
    this.editName = t.name;
    this.editDef = t.definition;
    this.editPage = t.pageNo;
    this.editNote = t.note;
  }

  private async saveEdit(): Promise<void> {
    const name = this.editName.trim();
    if (name === '') {
      return;
    }
    await db.updateTerm(this.editingId, name, this.editDef.trim(), this.editPage.trim(), this.editNote.trim());
    this.editingId = -1;
    await this.reload();
    this.onChanged();
  }

  private async remove(t: Term): Promise<void> {
    await db.deleteTerm(t.id);
    await this.reload();
    this.onChanged();
  }

  @Builder
  EditRow() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        TextInput({ text: this.editName, placeholder: '术语' }).height(32).width(130)
          .onChange((v: string) => { this.editName = v; })
        TextInput({ text: this.editPage, placeholder: '页码' }).height(32).width(70)
          .onChange((v: string) => { this.editPage = v; })
        TextInput({ text: this.editDef, placeholder: '释义' }).height(32).layoutWeight(1)
          .onChange((v: string) => { this.editDef = v; })
      }.width('100%')
      Row({ space: 8 }) {
        TextInput({ text: this.editNote, placeholder: '个人理解 / 备注（可选）' }).height(32).layoutWeight(1)
          .onChange((v: string) => { this.editNote = v; })
        Button('保存').height(32).backgroundColor($r('app.color.brand')).fontColor($r('app.color.on_brand')).onClick(() => { this.saveEdit(); })
        Button('取消').height(32).backgroundColor($r('app.color.bg_muted')).fontColor($r('app.color.text_primary'))
          .onClick(() => { this.editingId = -1; })
      }.width('100%')
    }
    .width('100%')
    .padding(8)
    .borderRadius(8)
    .backgroundColor($r('app.color.bg_muted'))
  }

  build() {
    Column({ space: 12 }) {
      Row({ space: 10 }) {
        Text('术语表').fontSize(18).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
        Text(`共 ${this.terms.length} 条`).fontSize(13).fontColor($r('app.color.text_muted'))
      }.width('100%')

      Row({ space: 8 }) {
        TextInput({ text: this.draftName, placeholder: '术语' }).height(36).width(130)
          .onChange((v: string) => { this.draftName = v; })
        TextInput({ text: this.draftPage, placeholder: '页码' }).height(36).width(70)
          .onChange((v: string) => { this.draftPage = v; })
        TextInput({ text: this.draftDef, placeholder: '释义' }).height(36).layoutWeight(1)
          .onChange((v: string) => { this.draftDef = v; })
          .onSubmit(() => { this.add(); })
        Button('添加').height(36).backgroundColor($r('app.color.brand')).fontColor($r('app.color.on_brand')).onClick(() => { this.add(); })
      }.width('100%')

      if (this.terms.length === 0) {
        Column({ space: 6 }) {
          Text('这一章还没有术语').fontSize(15).fontColor($r('app.color.text_muted'))
          Text('阅读中遇到的关键概念，随手记进来').fontSize(13).fontColor($r('app.color.text_muted'))
        }.width('100%').padding({ top: 40 }).alignItems(HorizontalAlign.Center)
      } else {
        List({ space: 6 }) {
          ForEach(this.terms, (t: Term) => {
            ListItem() {
              if (this.editingId === t.id) {
                this.EditRow()
              } else {
                Row({ space: 10 }) {
                  Column({ space: 2 }) {
                    Row({ space: 8 }) {
                      Text(t.name).fontSize(16).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
                      if (t.pageNo !== '') {
                        Text(t.pageNo).fontSize(12).fontColor($r('app.color.text_muted'))
                          .padding({ left: 6, right: 6 })
                          .borderRadius(999)
                          .backgroundColor($r('app.color.bg_muted'))
                      }
                    }
                    if (t.definition !== '') {
                      Text(t.definition).fontSize(14).fontColor($r('app.color.text_muted')).maxLines(2)
                    }
                    if (t.note !== '') {
                      Text(t.note).fontSize(13).fontColor($r('app.color.brand_text')).maxLines(2)
                    }
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)

                  Text('✎').fontSize(14).fontColor($r('app.color.text_muted')).onClick(() => { this.startEdit(t); })
                  Text('✕').fontSize(14).fontColor($r('app.color.text_muted')).onClick(() => { this.remove(t); })
                }
                .width('100%')
                .padding(10)
                .borderRadius(8)
                .backgroundColor($r('app.color.panel'))
                .border({ width: 1, color: $r('app.color.border') })
              }
            }
          }, (t: Term) => t.id.toString())
        }.layoutWeight(1).width('100%').scrollBar(BarState.Auto)
      }
    }
    .width('100%').height('100%')
    .padding(16)
    .alignItems(HorizontalAlign.Start)
  }
}
