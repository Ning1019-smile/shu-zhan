import { db } from '../database/Db';
import { Goal } from '../model/Models';

// 章节目标工作区：读前立的 flag，勾选即达成
@Component
export struct GoalPane {
  @Prop @Watch('onChapterChange') chapterId: number = -1;
  @State goals: Goal[] = [];
  @State draft: string = '';
  // 数据变化时通知父组件刷新统计
  onChanged: () => void = (): void => {};

  aboutToAppear(): void {
    this.reload();
  }

  onChapterChange(): void {
    this.reload();
  }

  private async reload(): Promise<void> {
    if (this.chapterId < 0) {
      this.goals = [];
      return;
    }
    this.goals = await db.getGoals(this.chapterId);
  }

  private async add(): Promise<void> {
    const t = this.draft.trim();
    if (t === '' || this.chapterId < 0) {
      return;
    }
    this.draft = '';
    await db.addGoal(this.chapterId, t);
    await this.reload();
  }

  private async toggle(g: Goal): Promise<void> {
    await db.setGoalDone(g.id, g.done === 1 ? 0 : 1);
    await this.reload();
    this.onChanged();
  }

  private async remove(g: Goal): Promise<void> {
    await db.deleteGoal(g.id);
    await this.reload();
    this.onChanged();
  }

  build() {
    Column({ space: 12 }) {
      Row({ space: 10 }) {
        Text('学习目标').fontSize(18).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
        Text(`${this.doneCount()}/${this.goals.length} 已达成`)
          .fontSize(13).fontColor($r('app.color.text_muted'))
        Progress({ value: this.doneCount(), total: Math.max(this.goals.length, 1), type: ProgressType.Linear })
          .color($r('app.color.brand')).style({ strokeWidth: 6 }).layoutWeight(1)
      }.width('100%')

      Row({ space: 8 }) {
        TextInput({ text: this.draft, placeholder: '新增一条学习目标，如：能区分逻辑结构与存储结构' })
          .height(36).layoutWeight(1)
          .onChange((v: string) => { this.draft = v; })
          .onSubmit(() => { this.add(); })
        Button('添加').height(36).backgroundColor($r('app.color.brand')).fontColor($r('app.color.on_brand')).onClick(() => { this.add(); })
      }.width('100%')

      if (this.goals.length === 0) {
        Column({ space: 6 }) {
          Text('还没有学习目标').fontSize(15).fontColor($r('app.color.text_muted'))
          Text('读这一章之前，先立几个 flag 吧').fontSize(13).fontColor($r('app.color.text_muted'))
        }.width('100%').padding({ top: 40 }).alignItems(HorizontalAlign.Center)
      } else {
        List({ space: 4 }) {
          ForEach(this.goals, (g: Goal) => {
            ListItem() {
              Row({ space: 10 }) {
                Text(g.done === 1 ? '✓' : '')
                  .fontSize(13).fontWeight(FontWeight.Bold)
                  .fontColor(g.done === 1 ? $r('app.color.brand_text') : Color.Transparent)
                  .textAlign(TextAlign.Center)
                  .width(20).height(20)
                  .borderRadius(6)
                  .backgroundColor(g.done === 1 ? $r('app.color.brand_soft') : $r('app.color.panel'))
                  .border({ width: 1.5, color: g.done === 1 ? $r('app.color.brand') : $r('app.color.border') })
                  .onClick(() => { this.toggle(g); })
                Text(g.content)
                  .fontSize(15).layoutWeight(1)
                  .fontColor(g.done === 1 ? $r('app.color.text_muted') : $r('app.color.text_primary'))
                  .decoration({ type: g.done === 1 ? TextDecorationType.LineThrough : TextDecorationType.None, color: $r('app.color.text_muted') })
                  .opacity(g.done === 1 ? 0.8 : 1)
                Text('✕').fontSize(14).fontColor($r('app.color.text_muted')).onClick(() => { this.remove(g); })
              }
              .width('100%').padding({ top: 6, bottom: 6, left: 4, right: 4 })
              .borderRadius(8)
            }
          }, (g: Goal) => `${g.id}_${g.done}`)
        }.layoutWeight(1).width('100%').scrollBar(BarState.Auto)
      }
    }
    .width('100%').height('100%')
    .padding(16)
    .alignItems(HorizontalAlign.Start)
  }

  private doneCount(): number {
    let n = 0;
    this.goals.forEach((g: Goal) => {
      if (g.done === 1) {
        n++;
      }
    });
    return n;
  }
}
