# Salon::Location の geohex を再生成するワンショットスクリプト
#
# 使用方法:
#   rails g oneshot:oneshot regenerate_geohex_for_salon_locations
#   で生成されたファイルに以下の内容をコピーしてください。
#
# 実行方法:
#   rails runner 'Oneshot::RegenerateGeohexForSalonLocations.run'
#   または rake oneshot:regenerate_geohex_for_salon_locations
#
# 想定するモデル構造:
#   - Salon::Location には latitude, longitude カラムがある
#   - geohex カラムがあり、nil または空文字のレコードを対象とする
#   - regenerate_geohex! または set_geohex のようなメソッドがある

class Oneshot::RegenerateGeohexForSalonLocations
  class << self
    def run
      log "Starting geohex regeneration for Salon::Location..."

      scope = target_locations
      total = scope.count

      log "Found #{total} locations with missing geohex"

      return log("No locations to process. Exiting.") if total.zero?

      processed = 0
      failed = []

      scope.find_each do |location|
        result = regenerate_geohex(location)
        if result
          processed += 1
        else
          failed << location.id
        end

        log_progress(processed, failed.size, total) if (processed + failed.size) % 100 == 0
      end

      log_summary(processed, failed, total)
    end

    private

    def target_locations
      # geohex が nil または空文字のレコードを対象
      # 必要に応じて条件を調整してください
      Salon::Location.where(geohex: [nil, ""])
    end

    def regenerate_geohex(location)
      # パターン1: regenerate_geohex! メソッドがある場合
      # location.regenerate_geohex!

      # パターン2: set_geohex コールバックを再実行する場合
      # location.set_geohex
      # location.save!

      # パターン3: GeoHex ライブラリを直接使用する場合
      # location.geohex = GeoHex.encode(location.latitude, location.longitude, level)
      # location.save!

      # パターン4: 単純に save! でコールバックを発火させる場合
      location.save!

      true
    rescue StandardError => e
      log "Failed to regenerate geohex for Location##{location.id}: #{e.message}"
      false
    end

    def log(message)
      Rails.logger.info "[Oneshot::RegenerateGeohexForSalonLocations] #{message}"
      puts "[#{Time.current}] #{message}"
    end

    def log_progress(processed, failed, total)
      percentage = ((processed + failed).to_f / total * 100).round(1)
      log "Progress: #{processed + failed}/#{total} (#{percentage}%) - Success: #{processed}, Failed: #{failed}"
    end

    def log_summary(processed, failed, total)
      log "=" * 60
      log "Completed geohex regeneration"
      log "Total processed: #{processed + failed.size}/#{total}"
      log "Success: #{processed}"
      log "Failed: #{failed.size}"
      log "Failed IDs: #{failed.join(', ')}" if failed.any?
      log "=" * 60
    end
  end
end
